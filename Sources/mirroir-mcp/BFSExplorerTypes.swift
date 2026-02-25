// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Value types used by BFSExplorer: frontier screens, path segments, and phase state.
// ABOUTME: Extracted from BFSExplorer to keep file sizes within the 500-line limit.

import Foundation

/// A screen in the BFS frontier queue waiting to be explored.
struct FrontierScreen: Sendable {
    /// Structural fingerprint identifying this screen.
    let fingerprint: String
    /// Element taps to replay from root to reach this screen.
    let pathFromRoot: [PathSegment]
    /// BFS depth (0 = root).
    let depth: Int
}

/// One step in the path from root to a frontier screen.
struct PathSegment: Sendable {
    /// Text of the element to tap.
    let elementText: String
    /// X coordinate of the element.
    let tapX: Double
    /// Y coordinate of the element.
    let tapY: Double
}

/// BFS explorer state machine phases.
enum BFSPhase {
    /// At root, ready to dequeue and process next frontier screen.
    case atRoot
    /// Navigating from root to a frontier screen by replaying path.
    case navigating(target: FrontierScreen, pathIndex: Int)
    /// At a frontier screen, exploring elements one by one.
    case exploring(screen: FrontierScreen)
    /// Navigating back to root after exploring a screen.
    case returning(depthRemaining: Int)
}
