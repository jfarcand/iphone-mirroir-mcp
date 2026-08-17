// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Merges results from multiple TextRecognizing backends into a single element list.
// ABOUTME: Decorator pattern — wraps N backends, concatenates their RawTextElement arrays.

import CoreGraphics
import Foundation
import HelperLib

/// Combines results from multiple `TextRecognizing` backends (e.g. Apple Vision OCR
/// and YOLO element detection) by running each and flat-mapping their outputs.
struct CompositeTextRecognizer: Sendable {
    private let backends: [any TextRecognizing]

    init(backends: [any TextRecognizing]) {
        self.backends = backends
    }

    /// Run every backend and merge their elements.
    ///
    /// A failing backend fails the whole call rather than quietly contributing
    /// nothing: a half-empty element list is indistinguishable from a screen
    /// that genuinely holds less text, which is how a broken engine hides.
    func recognizeText(
        in image: CGImage,
        windowSize: CGSize,
        contentBounds: CGRect
    ) throws -> [RawTextElement] {
        var elements: [RawTextElement] = []
        for backend in backends {
            do {
                elements += try backend.recognizeText(
                    in: image, windowSize: windowSize, contentBounds: contentBounds)
            } catch {
                throw TextRecognitionError.backendFailed(
                    name: String(describing: type(of: backend)), underlying: error)
            }
        }
        return elements
    }
}
