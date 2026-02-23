// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Detects exploration flow boundaries and cycles from screen capture history.
// ABOUTME: Uses ScreenFingerprint similarity to identify revisited screens and stuck states.

import HelperLib

/// Detects flow boundaries (back at start, cycles) during app exploration.
/// All methods are pure transformations using ScreenFingerprint for comparison.
enum FlowDetector {

    /// Minimum captures before flow boundary detection is active.
    /// Prevents false positives when the first capture is also the current screen.
    static let minScreensForFlowBoundary = 2

    /// Number of consecutive duplicate captures that triggers a "stuck" warning.
    static let stuckThreshold = 3

    /// Check if the current screen is similar to the starting screen.
    /// Returns true only when enough screens have been captured to avoid
    /// false positives on the initial capture.
    static func isBackAtStart(
        currentElements: [TapPoint],
        startElements: [TapPoint],
        screenCount: Int
    ) -> Bool {
        guard screenCount >= minScreensForFlowBoundary else { return false }
        return ScreenFingerprint.areEqual(currentElements, startElements)
    }

    /// Count consecutive duplicate capture rejections from the tail of the action log.
    /// A high count indicates the agent is stuck (tapping elements that don't change the screen).
    static func consecutiveDuplicates(in actionLog: [ExplorationAction]) -> Int {
        var count = 0
        for action in actionLog.reversed() {
            if action.wasDuplicate {
                count += 1
            } else {
                break
            }
        }
        return count
    }

    /// Count how many captured screens are similar to the given elements.
    /// Useful for detecting when the agent keeps returning to the same screen.
    static func visitCount(
        currentElements: [TapPoint],
        capturedScreens: [ExploredScreen]
    ) -> Int {
        capturedScreens.filter { screen in
            ScreenFingerprint.areEqual(screen.elements, currentElements)
        }.count
    }

    /// Check if the agent appears stuck based on consecutive duplicate captures.
    static func isStuck(actionLog: [ExplorationAction]) -> Bool {
        consecutiveDuplicates(in: actionLog) >= stuckThreshold
    }
}
