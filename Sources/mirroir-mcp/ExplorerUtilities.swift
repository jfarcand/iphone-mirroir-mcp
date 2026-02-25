// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Shared utility functions for app exploration: alert dismissal, back button navigation.
// ABOUTME: Used by BFSExplorer for common operations independent of traversal strategy.

import Foundation
import HelperLib

/// Shared utilities for app exploration, independent of traversal strategy (BFS/DFS).
/// Pure transformation: all static methods, no stored state.
enum ExplorerUtilities {

    /// Fraction of window width for the canonical back button X position.
    /// iOS UINavigationBar back buttons sit at roughly 11% from the left edge.
    static let backButtonXFraction = 0.112

    /// Fraction of window height for the canonical back button Y position.
    /// iOS UINavigationBar back buttons sit at roughly 13.5% from the top.
    static let backButtonYFraction = 0.135

    // MARK: - Alert Dismissal

    /// OCR the screen and dismiss any detected iOS alert before returning the result.
    /// If no alert is detected, the initial OCR result is returned directly (zero overhead).
    /// Retries up to `AlertDetector.maxDismissAttempts` times for persistent alerts.
    ///
    /// - Parameters:
    ///   - describer: Screen describer for OCR.
    ///   - input: Input provider for tap actions.
    /// - Returns: Clean OCR result after dismissing any alerts, or nil if OCR fails.
    static func dismissAlertIfPresent(
        describer: ScreenDescribing,
        input: InputProviding
    ) -> ScreenDescriber.DescribeResult? {
        guard var result = describer.describe(skipOCR: false) else { return nil }

        for _ in 0..<AlertDetector.maxDismissAttempts {
            guard let alert = AlertDetector.detectAlert(elements: result.elements) else {
                return result
            }
            // Tap the dismiss target
            _ = input.tap(x: alert.dismissTarget.tapX, y: alert.dismissTarget.tapY)
            usleep(EnvConfig.stepSettlingDelayMs * 1000)
            // Re-OCR to get clean screen
            guard let cleanResult = describer.describe(skipOCR: false) else { return nil }
            result = cleanResult
        }

        // After max attempts, return whatever we have
        return result
    }

    // MARK: - Back Button Navigation

    /// Find and tap the "<" back button on the current screen.
    /// iPhone Mirroring does not support iOS edge-swipe-back gestures (neither
    /// scroll wheel nor touch-drag triggers UIScreenEdgePanGestureRecognizer).
    /// Tapping the OCR-detected back chevron is the only reliable backtrack method.
    ///
    /// First attempts to find the "<" chevron via OCR elements. If OCR misses the
    /// back button, falls back to tapping at the canonical iOS navigation bar position.
    ///
    /// - Parameters:
    ///   - elements: OCR elements from the current screen (avoids redundant OCR call).
    ///   - input: Input provider for tap actions.
    ///   - windowSize: Window size for fallback position calculation.
    /// - Returns: Always `true` (canonical position fallback guarantees a tap).
    @discardableResult
    static func tapBackButton(
        elements: [TapPoint],
        input: InputProviding,
        windowSize: CGSize
    ) -> Bool {
        let topZone = windowSize.height * NavigationHintDetector.topZoneFraction
        if let backButton = elements.first(where: { element in
            let trimmed = element.text.trimmingCharacters(in: .whitespaces)
            return NavigationHintDetector.backChevronPatterns.contains(trimmed)
                && element.tapY <= topZone
        }) {
            _ = input.tap(x: backButton.tapX, y: backButton.tapY)
            usleep(EnvConfig.stepSettlingDelayMs * 1000)
            return true
        }

        // OCR sometimes fails to detect the "<" chevron, but the back button is
        // at a predictable position in the iOS navigation bar. Tap there as fallback.
        let fallbackX = windowSize.width * backButtonXFraction
        let fallbackY = windowSize.height * backButtonYFraction
        _ = input.tap(x: fallbackX, y: fallbackY)
        usleep(EnvConfig.stepSettlingDelayMs * 1000)
        return true
    }

    // MARK: - Combined Navigate Back

    /// Tap back and OCR the resulting screen. Combines tapBackButton + dismissAlertIfPresent.
    ///
    /// - Parameters:
    ///   - currentElements: Elements from the current screen (for back button detection).
    ///   - input: Input provider for tap actions.
    ///   - describer: Screen describer for OCR.
    ///   - windowSize: Window size for fallback position calculation.
    /// - Returns: OCR result of the screen after tapping back, or nil if OCR fails.
    static func navigateBack(
        currentElements: [TapPoint],
        input: InputProviding,
        describer: ScreenDescribing,
        windowSize: CGSize
    ) -> ScreenDescriber.DescribeResult? {
        tapBackButton(elements: currentElements, input: input, windowSize: windowSize)
        return dismissAlertIfPresent(describer: describer, input: input)
    }
}
