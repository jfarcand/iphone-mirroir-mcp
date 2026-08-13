// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: AI vision-based screen describer using embacle or compatible vision API.
// ABOUTME: Implements ScreenDescribing by sending screenshots to a vision model instead of local OCR.

import CoreGraphics
import Foundation
import HelperLib
import ImageIO

/// Screen describer that uses an AI vision model to identify UI elements.
/// Captures a screenshot, resizes it for the vision API, sends it with a system prompt,
/// and parses the response into TapPoints in window-point space.
final class VisionScreenDescriber: @unchecked Sendable {
    private let bridge: any WindowBridging
    private let capture: any ScreenCapturing
    private let agentConfig: AgentConfig
    private let targetImageWidth: Int

    init(
        bridge: any WindowBridging,
        capture: any ScreenCapturing,
        agentConfig: AgentConfig,
        targetImageWidth: Int = EnvConfig.visionImageWidth
    ) {
        self.bridge = bridge
        self.capture = capture
        self.agentConfig = agentConfig
        self.targetImageWidth = targetImageWidth
    }

    func describe() -> ScreenDescriber.DescribeResult? {
        // Single capture call resolves window info and screenshot together
        guard let result = capture.captureWithInfo() else { return nil }
        let info = result.info
        var data = result.data

        // In Larger zoom mode, the screenshot has dark borders around the
        // iOS content. Crop them before sending to the vision model so it
        // only sees actual UI elements, not black bars.
        if let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
           let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) {
            let contentBounds = ContentBoundsDetector.detect(image: image)
            let widthMargin = Double(image.width) * 0.05
            let heightMargin = Double(image.height) * 0.05
            let hasBorders = Double(contentBounds.width) < Double(image.width) - widthMargin
                && Double(contentBounds.height) < Double(image.height) - heightMargin
            if hasBorders,
               let cropped = image.cropping(to: CGRect(
                   x: Int(contentBounds.minX), y: Int(contentBounds.minY),
                   width: Int(contentBounds.width), height: Int(contentBounds.height)
               )) {
                DebugLog.log("vision", "Larger mode detected — cropping borders before resize")
                let mutableData = NSMutableData()
                if let dest = CGImageDestinationCreateWithData(
                    mutableData as CFMutableData, "public.png" as CFString, 1, nil
                ) {
                    CGImageDestinationAddImage(dest, cropped, nil)
                    if CGImageDestinationFinalize(dest) {
                        data = mutableData as Data
                    }
                }
            }
        }

        // Resize for the vision API (Retina PNGs are too large)
        guard let resized = ImageResizer.resize(
            pngData: data, targetWidth: targetImageWidth, windowSize: info.size
        ) else {
            DebugLog.log("vision", "describe: image resize failed")
            return nil
        }

        let visionStart = CFAbsoluteTimeGetCurrent()

        // Send to vision model with resized image dimensions so the model
        // knows the exact coordinate space to use for x/y values.
        guard let responseText = sendVisionRequest(
            imageBase64: resized.base64,
            imageWidth: resized.width,
            imageHeight: resized.height
        ) else {
            DebugLog.log("vision", "describe: vision API request failed")
            return nil
        }

        let visionMs = Int((CFAbsoluteTimeGetCurrent() - visionStart) * 1000)
        DebugLog.log("vision", "describe: response received in \(visionMs)ms")

        // Parse response and scale coordinates to window points
        let (elements, hints) = VisionResponseParser.parse(
            responseText: responseText,
            scaleX: resized.scaleX,
            scaleY: resized.scaleY
        )

        DebugLog.log("vision", "describe: \(elements.count) elements, \(hints.count) hints, " +
            "scale=(\(String(format: "%.2f", resized.scaleX)),\(String(format: "%.2f", resized.scaleY))) " +
            "time=\(visionMs)ms")

        // Grid overlay on the original (full-resolution) screenshot for the MCP client
        let griddedData = GridOverlay.addOverlay(to: data, windowSize: info.size) ?? data
        let base64 = griddedData.base64EncodedString()

        return ScreenDescriber.DescribeResult(
            elements: elements, hints: hints,
            screenshotBase64: base64, ocrTimeMs: visionMs
        )
    }

    // MARK: - Vision API Request

    /// Send the screenshot to the configured vision model and return the response text.
    private func sendVisionRequest(
        imageBase64: String, imageWidth: Int, imageHeight: Int
    ) -> String? {
        let baseURL = agentConfig.baseURL ?? defaultAgentBaseURL
        guard let url = URL(string: baseURL + "/v1/chat/completions") else { return nil }

        let systemPrompt = loadDiagnosisPrompt(filename: "screen-describe.md")

        // Build multipart content with image for OpenAI-compatible vision API.
        // Include the resized image dimensions so the model returns coordinates
        // in the correct pixel space regardless of macOS zoom mode.
        let userContent: [[String: Any]] = [
            ["type": "text", "text": "This image is \(imageWidth)x\(imageHeight) pixels. "
                + "Return a JSON array of all tappable UI elements. "
                + "Coordinates must be in pixel space (0 to \(imageWidth) for x, 0 to \(imageHeight) for y). "
                + "ONLY output the JSON array, nothing else."],
            ["type": "image_url", "image_url": [
                "url": "data:image/png;base64,\(imageBase64)",
            ]],
        ]

        // Use copilot_headless for vision (supports image payloads)
        let modelName = resolveVisionModel()

        let requestBody: [String: Any] = [
            "model": modelName,
            "max_tokens": EnvConfig.visionMaxTokens,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: requestBody) else {
            return nil
        }

        var headers = ["Content-Type": "application/json"]

        // Support optional auth
        if let apiKeyEnv = agentConfig.apiKeyEnvVar,
           let apiKey = ProcessInfo.processInfo.environment[apiKeyEnv],
           !apiKey.isEmpty {
            headers["Authorization"] = "Bearer \(apiKey)"
        }

        guard let responseData = sendAgentHTTPRequest(
            url: url, headers: headers, body: body,
            timeoutSeconds: EnvConfig.embacleTimeoutSeconds
        ) else {
            return nil
        }

        return extractChatCompletionText(from: responseData)
    }

    /// Resolve the vision-capable model name.
    /// User override via `visionModel` setting takes priority. Otherwise,
    /// embacle defaults to `copilot_headless` (supports image payloads).
    private func resolveVisionModel() -> String {
        let override = EnvConfig.visionModel
        if !override.isEmpty {
            return override
        }
        if agentConfig.provider == .embacle {
            return defaultAgentModel
        }
        return agentConfig.model ?? defaultAgentModel
    }
}
