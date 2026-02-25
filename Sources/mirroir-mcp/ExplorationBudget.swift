// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Budget constraints for autonomous app exploration (depth, screens, time, actions).
// ABOUTME: Prevents runaway exploration by enforcing configurable limits on DFS traversal.

import Foundation

/// Budget constraints for autonomous app exploration.
/// Prevents runaway exploration by enforcing limits on depth, screen count,
/// elapsed time, and per-screen action count.
struct ExplorationBudget: Sendable {

    /// Maximum DFS depth before forcing backtrack.
    let maxDepth: Int

    /// Maximum distinct screens before stopping exploration.
    let maxScreens: Int

    /// Maximum wall-clock seconds before stopping exploration.
    let maxTimeSeconds: Int

    /// Maximum elements to try tapping on a single screen before moving on.
    let maxActionsPerScreen: Int

    /// Maximum scroll attempts per screen to reveal hidden content.
    let scrollLimit: Int

    /// Maximum scout taps on a single screen before forcing transition to dive phase.
    let maxScoutsPerScreen: Int

    /// Element text patterns that should never be tapped (destructive or dangerous actions).
    let skipPatterns: [String]

    /// Memberwise init with a default value for `maxScoutsPerScreen` to preserve backward
    /// compatibility at all existing call sites that predate the scout phase feature.
    init(
        maxDepth: Int,
        maxScreens: Int,
        maxTimeSeconds: Int,
        maxActionsPerScreen: Int,
        scrollLimit: Int,
        maxScoutsPerScreen: Int = 8,
        skipPatterns: [String]
    ) {
        self.maxDepth = maxDepth
        self.maxScreens = maxScreens
        self.maxTimeSeconds = maxTimeSeconds
        self.maxActionsPerScreen = maxActionsPerScreen
        self.scrollLimit = scrollLimit
        self.maxScoutsPerScreen = maxScoutsPerScreen
        self.skipPatterns = skipPatterns
    }

    /// Default budget suitable for most mobile app explorations.
    /// Skip patterns are empty — they come from permissions.json `skipElements` field.
    static let `default` = ExplorationBudget(
        maxDepth: 6,
        maxScreens: 30,
        maxTimeSeconds: 300,
        maxActionsPerScreen: 5,
        scrollLimit: 3,
        maxScoutsPerScreen: 8,
        skipPatterns: []
    )

    /// Check if the exploration budget is exhausted based on current state.
    ///
    /// - Parameters:
    ///   - depth: Current DFS depth.
    ///   - screenCount: Number of distinct screens visited so far.
    ///   - elapsedSeconds: Wall-clock seconds since exploration started.
    /// - Returns: `true` if any budget limit has been reached.
    func isExhausted(depth: Int, screenCount: Int, elapsedSeconds: Int) -> Bool {
        depth >= maxDepth || screenCount >= maxScreens || elapsedSeconds >= maxTimeSeconds
    }

    /// Check if an element should be skipped based on its text.
    /// Case-insensitive containment check against skip patterns.
    func shouldSkipElement(text: String) -> Bool {
        let lowered = text.lowercased()
        return skipPatterns.contains { pattern in
            lowered.contains(pattern.lowercased())
        }
    }
}
