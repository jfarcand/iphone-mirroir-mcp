// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Registers screen-related MCP tools: screenshot, describe_screen, start/stop recording.
// ABOUTME: Each tool maps MCP JSON-RPC calls to the capture, recorder, and describer subsystems.

import Foundation
import HelperLib

extension MirroirMCP {
    static func registerScreenTools(
        server: MCPServer,
        registry: TargetRegistry
    ) {
        // screenshot — capture the mirroring window
        server.registerTool(MCPToolDefinition(
            name: "screenshot",
            description: """
                Capture a screenshot of the iPhone Mirroring window. \
                Returns the current screen content as a PNG image. \
                Use this to see what is displayed on the mirrored iPhone.

                By default the capture waits for the screen to stop changing, \
                because the mirrored frame lags the device: a capture taken \
                immediately after an action can still show the pre-action \
                screen. Never retry an action that "looks like a no-op" — the \
                first one landed, so the retry fires on the next screen and \
                mis-taps. Use settle_ms to tune the wait, or 0 to disable it.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "settle_ms": .object([
                        "type": .string("integer"),
                        "description": .string(
                            "How long to wait for two consecutive identical frames before "
                            + "returning, in milliseconds. 0 returns the first frame "
                            + "immediately, which may be stale. Defaults to the "
                            + "frameSettleTimeoutUs setting."),
                    ]),
                ]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                let bridge = ctx.bridge
                let capture = ctx.capture

                guard bridge.findProcess() != nil else {
                    return .error("Target '\(ctx.name)' is not running")
                }

                let state = bridge.getState()
                if state == .paused {
                    if let menuBridge = bridge as? (any MenuActionCapable) {
                        _ = menuBridge.pressResume()
                        usleep(EnvConfig.resumeFromPausedUs)
                    }
                }

                // A settle window of 0 is an explicit opt-out: the caller wants
                // the first available frame and accepts that it may be stale.
                let settleUs = args["settle_ms"]?.asInt().map { UInt32(max(0, $0)) * 1000 }
                    ?? EnvConfig.frameSettleTimeoutUs
                let base64 = settleUs == 0
                    ? capture.captureBase64()
                    : capture.captureSettledBase64(timeoutUs: settleUs)

                guard let base64 else {
                    return .error(
                        "Failed to capture screenshot. Is the '\(ctx.name)' window visible?")
                }

                return .image(base64)
            }
        ))

        // describe_screen — OCR-based screen element detection with tap coordinates
        server.registerTool(MCPToolDefinition(
            name: "describe_screen",
            description: """
                Analyze the iPhone screen using OCR and return all visible text elements \
                with their exact tap coordinates. Use this instead of visually estimating \
                positions from screenshots. Returns both a structured text list of elements \
                and the screenshot image. Coordinates are in the same point system as the \
                tap tool (0,0 = top-left of mirroring window). \
                Set scroll to true to scroll through the full page and collect all elements \
                with page-absolute Y coordinates.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "scroll": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Scroll through the full page to collect all elements with page-absolute Y coordinates (default: false)"),
                    ]),
                    "omit_screenshot": .object([
                        "type": .string("boolean"),
                        "description": .string(
                            "Omit the screenshot image from the response to save context window space (default: uses MIRROIR_OMIT_SCREENSHOT env var, or false)"),
                    ]),
                ]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                let bridge = ctx.bridge
                let describer = ctx.describer

                guard bridge.findProcess() != nil else {
                    return .error("Target '\(ctx.name)' is not running")
                }
                let state = bridge.getState()
                if state == .paused {
                    if let menuBridge = bridge as? (any MenuActionCapable) {
                        _ = menuBridge.pressResume()
                        usleep(EnvConfig.resumeFromPausedUs)
                    }
                }

                let scrollEnabled = args["scroll"]?.asBool() ?? false
                let omitScreenshot = args["omit_screenshot"]?.asBool() ?? EnvConfig.describeScreenOmitScreenshot

                // Full-page scroll mode: collect all elements across viewports
                if scrollEnabled {
                    let input = ctx.input
                    guard let scrollResult = describer.describeFullPage(
                        input: input, bridge: bridge
                    ) else {
                        return .error(
                            "Failed to capture/analyze screen. Is the '\(ctx.name)' window visible?")
                    }

                    var lines = ["Screen elements (page-absolute tap coordinates in points):"]
                    for el in scrollResult.elements.sorted(by: { $0.tapY < $1.tapY }) {
                        lines.append("- \"\(el.text)\" at (\(Int(el.tapX)), \(Int(el.tapY)))")
                    }
                    if scrollResult.elements.isEmpty {
                        lines.append("(no text detected)")
                    }
                    lines.append("")
                    lines.append("_meta: scroll_count=\(scrollResult.scrollCount) total_offset=\(Int(scrollResult.totalScrollOffset)) element_count=\(scrollResult.elements.count)")
                    let description = lines.joined(separator: "\n")

                    let scrollContent: [MCPContent] = omitScreenshot
                        ? [.text(description)]
                        : [.text(description), .image(scrollResult.screenshotBase64, mimeType: "image/png")]
                    return MCPToolResult(content: scrollContent, isError: false)
                }

                guard let result = describer.describe() else {
                    return .error(
                        "Failed to capture/analyze screen. Is the '\(ctx.name)' window visible?")
                }

                var lines = ["Screen elements (tap coordinates in points):"]
                for el in result.elements.sorted(by: { $0.tapY < $1.tapY }) {
                    lines.append("- \"\(el.text)\" at (\(Int(el.tapX)), \(Int(el.tapY)))")
                }
                if let failure = result.ocrFailure {
                    // Never report a broken engine as a blank screen: the two
                    // look identical in the element list and only one of them
                    // means the screen is actually empty.
                    lines.append("(OCR FAILED — text recognition did not run: \(failure))")
                    lines.append("Any icons and hints below come from the non-OCR path; "
                        + "the text layer is missing, not empty.")
                } else if result.elements.isEmpty {
                    lines.append("(no text detected)")
                }
                if !result.icons.isEmpty {
                    lines.append("")
                    lines.append("Unlabeled icons (estimated positions):")
                    for icon in result.icons.sorted(by: { $0.tapX < $1.tapX }) {
                        lines.append("- Icon at (\(Int(icon.tapX)), \(Int(icon.tapY))), ~\(Int(icon.estimatedSize))x\(Int(icon.estimatedSize))pt")
                    }
                }
                if !result.hints.isEmpty {
                    lines.append("")
                    lines.append("Hints:")
                    for hint in result.hints {
                        lines.append("- \(hint)")
                    }
                }
                lines.append("")
                lines.append("_meta: ocr_time_ms=\(result.ocrTimeMs) recognition_level=\(EnvConfig.ocrRecognitionLevel) element_count=\(result.elements.count)"
                    + (result.ocrFailure == nil ? "" : " ocr_status=failed"))
                let description = lines.joined(separator: "\n")

                let content: [MCPContent] = omitScreenshot
                    ? [.text(description)]
                    : [.text(description), .image(result.screenshotBase64, mimeType: "image/png")]
                return MCPToolResult(content: content, isError: false)
            }
        ))

        // start_recording — begin video recording of the mirroring window
        server.registerTool(MCPToolDefinition(
            name: "start_recording",
            description: """
                Start recording a video of the mirrored iPhone screen. \
                Records the iPhone Mirroring window as a .mov file. \
                Use stop_recording to end the recording and get the file path. \
                Requires Screen Recording permission in System Preferences.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "output_path": .object([
                        "type": .string("string"),
                        "description": .string(
                            "Optional file path for the recording (default: temp directory)"),
                    ])
                ]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                let recorder = ctx.recorder

                let outputPath = args["output_path"]?.asString()

                if let error = recorder.startRecording(outputPath: outputPath) {
                    return .error(error)
                }
                return .text("Recording started")
            }
        ))

        // stop_recording — stop video recording and return the file path
        server.registerTool(MCPToolDefinition(
            name: "stop_recording",
            description: """
                Stop the current video recording and return the file path. \
                Must be called after start_recording. Returns the path to \
                the recorded .mov file.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([:]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                let recorder = ctx.recorder

                let result = recorder.stopRecording()
                if let error = result.error {
                    return .error(error)
                }
                guard let path = result.filePath else {
                    return .error("Recording stopped but no file was produced")
                }
                return .text("Recording saved to: \(path)")
            }
        ))
    }
}
