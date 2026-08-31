// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Reduces a captured PNG frame to its decoded pixel bytes for equality comparison.
// ABOUTME: Lets ScreenCapture detect a settled frame without comparing encoder-dependent PNG bytes.

import CoreGraphics
import Foundation
import ImageIO

/// Reduces an encoded screenshot to a value that compares equal only when the
/// two frames show the same pixels (pure transformation pattern).
///
/// Comparing the PNG bytes directly is not reliable: two encodings of identical
/// pixels can differ, and any metadata the encoder writes changes with every
/// capture. Decoding to raw pixels sidesteps both problems, so a comparison
/// answers the question actually being asked — "has the screen stopped
/// changing?" — rather than "did the encoder emit the same file?".
enum FrameFingerprint {

    /// Decode a PNG frame to its raw pixel bytes.
    ///
    /// Returns `nil` when the data is not a decodable image, in which case the
    /// caller must treat the comparison as inconclusive rather than as a match —
    /// two undecodable frames are not evidence that the screen has settled.
    static func pixels(of png: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let provider = image.dataProvider,
              let pixels = provider.data
        else { return nil }
        return pixels as Data
    }

    /// Whether two encoded frames show the same pixels.
    ///
    /// Returns `false` when either frame fails to decode, so an unreadable
    /// capture never counts as "settled".
    static func sameContent(_ lhs: Data, _ rhs: Data) -> Bool {
        guard let left = pixels(of: lhs), let right = pixels(of: rhs) else { return false }
        return left == right
    }
}
