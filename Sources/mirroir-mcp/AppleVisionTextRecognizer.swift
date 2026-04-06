// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Apple Vision framework backend for text recognition.
// ABOUTME: Converts VNRecognizeTextRequest observations into RawTextElements in window-point space.

import CoreGraphics
import Foundation
import HelperLib
import Vision

/// Recognizes text in screenshots using Apple's Vision framework (`VNRecognizeTextRequest`).
/// Coordinates are transformed from Vision's normalized bottom-left origin to
/// window-point top-left origin, with content-bounds scaling applied.
struct AppleVisionTextRecognizer: Sendable {

    func recognizeText(
        in image: CGImage,
        windowSize: CGSize,
        contentBounds: CGRect
    ) -> [RawTextElement] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = EnvConfig.ocrRecognitionLevel == "fast" ? .fast : .accurate
        request.usesLanguageCorrection = EnvConfig.ocrLanguageCorrection
        request.recognitionLanguages = EnvConfig.ocrLanguages

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        guard let observations = request.results else { return [] }

        let windowWidth = Double(windowSize.width)
        let windowHeight = Double(windowSize.height)

        // The display backing scale is uniform (same for X and Y on macOS).
        // Derive it from the X dimension, which is reliable — screencapture
        // does not add extra horizontal content beyond the window bounds.
        let backingScale = Double(image.width) / windowWidth

        // Image dimensions in point space. imagePointHeight may exceed
        // windowHeight when screencapture includes window chrome (rounded
        // corners, home indicator area) beyond the AX-reported window size.
        let imagePointHeight = Double(image.height) / backingScale

        // Content-to-window scaling: only applied when ContentBoundsDetector
        // found SIGNIFICANT dark borders (Larger display mode). Small
        // differences (< 5% per axis) are ignored — they come from the
        // phone's rounded corners and home indicator, not from display mode
        // borders. In Larger mode the content is typically 10-20% smaller.
        let widthMargin = Double(image.width) * 0.05
        let heightMargin = Double(image.height) * 0.05
        let bordersDetected = Double(contentBounds.width) < Double(image.width) - widthMargin
            && Double(contentBounds.height) < Double(image.height) - heightMargin

        let xScale: Double
        let yScale: Double
        if bordersDetected {
            let contentWidth = Double(contentBounds.width) / backingScale
            let contentHeight = Double(contentBounds.height) / backingScale
            xScale = windowWidth / max(contentWidth, 1.0)
            yScale = windowHeight / max(contentHeight, 1.0)
        } else {
            xScale = 1.0
            yScale = 1.0
        }

        if bordersDetected {
            DebugLog.log("OCR", "Larger-mode scaling: contentBounds=\(Int(contentBounds.width))x\(Int(contentBounds.height)) yScale=\(String(format: "%.3f", yScale))")
        }

        // Convert Vision normalized coordinates (origin: bottom-left) to
        // tap-point coordinates (origin: top-left of mirroring window).
        // Vision normalizes to the full image, so we convert through the
        // actual image dimensions (imagePointHeight), not windowHeight.
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let bbox = observation.boundingBox
            return RawTextElement(
                text: candidate.string,
                tapX: (bbox.midX * windowWidth) * xScale,
                textTopY: ((1.0 - bbox.maxY) * imagePointHeight) * yScale,
                textBottomY: ((1.0 - bbox.minY) * imagePointHeight) * yScale,
                bboxWidth: bbox.width * windowWidth * xScale,
                confidence: candidate.confidence
            )
        }
    }
}
