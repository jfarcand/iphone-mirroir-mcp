// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Extracts comparable fingerprints from OCR elements for screen deduplication.
// ABOUTME: Filters status bar noise and sorts text to detect when a screen is unchanged.

import Foundation
import HelperLib

/// Extracts a comparable fingerprint from a screen's OCR elements.
/// Used to detect when a capture action produced no screen change (failed tap).
/// Filters the same status bar noise as `LandmarkPicker` but keeps all remaining text
/// for full-screen comparison rather than picking a single landmark.
enum ScreenFingerprint {

    /// Similarity threshold above which two screens are considered the same.
    /// Jaccard index: 0.0 = completely different, 1.0 = identical.
    /// At 0.8, scrolled list views (60-80% element retention) are detected as duplicates
    /// while real navigation changes (different header/landmark) are still distinct.
    static let screenSimilarityThreshold: Double = 0.8

    /// Extract a sorted array of meaningful text from OCR elements.
    /// Filters out status bar elements (tapY < 80), time patterns, and bare numbers.
    static func extract(from elements: [TapPoint]) -> [String] {
        elements
            .filter { el in
                el.tapY >= LandmarkPicker.statusBarMaxY
                    && !LandmarkPicker.isTimePattern(el.text)
                    && !LandmarkPicker.isBareNumber(el.text)
            }
            .map(\.text)
            .sorted()
    }

    /// Compute Jaccard similarity between two fingerprints (0.0–1.0).
    /// Returns the size of the intersection divided by the size of the union.
    static func similarity(_ lhs: [TapPoint], _ rhs: [TapPoint]) -> Double {
        let left = Set(extract(from: lhs))
        let right = Set(extract(from: rhs))
        let union = left.union(right)
        guard !union.isEmpty else { return 1.0 }  // both empty = identical
        return Double(left.intersection(right).count) / Double(union.count)
    }

    /// Compare two screens by their fingerprints.
    /// Returns `true` if the Jaccard similarity meets or exceeds the threshold.
    static func areEqual(_ lhs: [TapPoint], _ rhs: [TapPoint]) -> Bool {
        similarity(lhs, rhs) >= screenSimilarityThreshold
    }
}
