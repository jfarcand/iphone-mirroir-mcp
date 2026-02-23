// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for ExplorationSession lifecycle: start, capture, finalize, modes, and goals.
// ABOUTME: Verifies thread-safe accumulation, state transitions, and manifest-mode goal queue.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class ExplorationSessionTests: XCTestCase {

    // MARK: - Start and Capture

    func testStartAndCapture() {
        let session = ExplorationSession()

        XCTAssertFalse(session.active)
        XCTAssertEqual(session.screenCount, 0)

        session.start(appName: "Settings", goal: "check version")

        XCTAssertTrue(session.active)
        XCTAssertEqual(session.currentAppName, "Settings")
        XCTAssertEqual(session.currentGoal, "check version")
        XCTAssertEqual(session.screenCount, 0)

        session.capture(
            elements: [TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95)],
            hints: ["Navigation bar detected"],
            actionType: nil,
            arrivedVia: nil,
            screenshotBase64: "base64screenshot1"
        )

        XCTAssertEqual(session.screenCount, 1)
    }

    // MARK: - Finalize Returns Screens In Order

    func testFinalizeReturnsScreensInOrder() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "explore")

        session.capture(
            elements: [TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95)],
            hints: [],
            actionType: nil,
            arrivedVia: nil,
            screenshotBase64: "screen0"
        )
        session.capture(
            elements: [TapPoint(text: "About", tapX: 205, tapY: 400, confidence: 0.92)],
            hints: [],
            actionType: "tap",
            arrivedVia: "General",
            screenshotBase64: "screen1"
        )
        session.capture(
            elements: [TapPoint(text: "iOS Version", tapX: 205, tapY: 300, confidence: 0.88)],
            hints: [],
            actionType: "tap",
            arrivedVia: "About",
            screenshotBase64: "screen2"
        )

        let data = session.finalize()
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.screens.count, 3)
        XCTAssertEqual(data?.screens[0].index, 0)
        XCTAssertEqual(data?.screens[1].index, 1)
        XCTAssertEqual(data?.screens[2].index, 2)
        XCTAssertEqual(data?.screens[0].screenshotBase64, "screen0")
        XCTAssertEqual(data?.screens[1].arrivedVia, "General")
        XCTAssertEqual(data?.screens[1].actionType, "tap")
        XCTAssertEqual(data?.screens[2].arrivedVia, "About")
        XCTAssertEqual(data?.screens[2].actionType, "tap")
        XCTAssertEqual(data?.appName, "Settings")
        XCTAssertEqual(data?.goal, "explore")
    }

    // MARK: - Finalize Clears State

    func testFinalizeClearsState() {
        let session = ExplorationSession()
        session.start(appName: "Maps", goal: "search")

        session.capture(
            elements: [TapPoint(text: "Search", tapX: 100, tapY: 150, confidence: 0.9)],
            hints: [],
            actionType: nil,
            arrivedVia: nil,
            screenshotBase64: "img"
        )

        let data = session.finalize()
        XCTAssertNotNil(data)

        // Session should be inactive after finalize
        XCTAssertFalse(session.active)
        XCTAssertEqual(session.screenCount, 0)
        XCTAssertEqual(session.currentAppName, "")
        XCTAssertEqual(session.currentGoal, "")

        // Second finalize returns nil
        let secondFinalize = session.finalize()
        XCTAssertNil(secondFinalize)
    }

    // MARK: - Active Flags

    func testActiveFlags() {
        let session = ExplorationSession()

        XCTAssertFalse(session.active, "Session should be inactive before start")

        session.start(appName: "Notes", goal: "")
        XCTAssertTrue(session.active, "Session should be active after start")

        _ = session.finalize()
        XCTAssertFalse(session.active, "Session should be inactive after finalize")
    }

    // MARK: - Start Resets Previous Session

    func testStartResetsExistingSession() {
        let session = ExplorationSession()
        session.start(appName: "OldApp", goal: "old goal")

        session.capture(
            elements: [TapPoint(text: "Old Screen", tapX: 100, tapY: 100, confidence: 0.9)],
            hints: [],
            actionType: nil,
            arrivedVia: nil,
            screenshotBase64: "old"
        )

        XCTAssertEqual(session.screenCount, 1)

        // Starting a new session resets the old one
        session.start(appName: "NewApp", goal: "new goal")
        XCTAssertEqual(session.currentAppName, "NewApp")
        XCTAssertEqual(session.currentGoal, "new goal")
        XCTAssertEqual(session.screenCount, 0)
        XCTAssertTrue(session.active)
    }

    // MARK: - Duplicate Screen Rejection

    func testCaptureDuplicateScreenIsRejected() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test dedup")

        let elements = [
            TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95),
            TapPoint(text: "Privacy", tapX: 205, tapY: 400, confidence: 0.93),
        ]

        let first = session.capture(
            elements: elements, hints: [], actionType: nil,
            arrivedVia: nil, screenshotBase64: "img1")
        XCTAssertTrue(first, "First capture should be accepted")
        XCTAssertEqual(session.screenCount, 1)

        let second = session.capture(
            elements: elements, hints: [], actionType: "tap",
            arrivedVia: "General", screenshotBase64: "img2")
        XCTAssertFalse(second, "Duplicate screen should be rejected")
        XCTAssertEqual(session.screenCount, 1, "Count should not increase on duplicate")
    }

    func testCaptureDifferentScreenIsAccepted() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test dedup")

        let first = session.capture(
            elements: [TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img1")
        XCTAssertTrue(first)

        let second = session.capture(
            elements: [TapPoint(text: "About", tapX: 205, tapY: 400, confidence: 0.92)],
            hints: [], actionType: "tap", arrivedVia: "General", screenshotBase64: "img2")
        XCTAssertTrue(second, "Different screen should be accepted")
        XCTAssertEqual(session.screenCount, 2)
    }

    func testCaptureDuplicateAfterDifferentIsRejected() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test dedup")

        let elementsA = [TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95)]
        let elementsB = [TapPoint(text: "About", tapX: 205, tapY: 400, confidence: 0.92)]

        session.capture(
            elements: elementsA, hints: [], actionType: nil,
            arrivedVia: nil, screenshotBase64: "img1")
        session.capture(
            elements: elementsB, hints: [], actionType: "tap",
            arrivedVia: "General", screenshotBase64: "img2")

        let duplicate = session.capture(
            elements: elementsB, hints: [], actionType: "tap",
            arrivedVia: "About", screenshotBase64: "img3")
        XCTAssertFalse(duplicate, "B after B should be rejected")
        XCTAssertEqual(session.screenCount, 2, "Count should stay at 2")
    }

    // MARK: - Scroll Overlap Detection

    func testScrolledViewTreatedAsDuplicate() {
        // 80%+ element overlap simulates a slight scroll — should be rejected
        // Jaccard = 9 / (9 + 1 + 1) = 9/11 ≈ 0.818 → above 0.8 threshold
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test scroll dedup")

        let shared = (1...9).map {
            TapPoint(text: "Row \($0)", tapX: 205, tapY: Double(100 + $0 * 50), confidence: 0.95)
        }
        let screenA = shared + [
            TapPoint(text: "Top Only", tapX: 205, tapY: 90, confidence: 0.95),
        ]
        let screenB = shared + [
            TapPoint(text: "Bottom New", tapX: 205, tapY: 600, confidence: 0.95),
        ]

        let first = session.capture(
            elements: screenA, hints: [], actionType: nil,
            arrivedVia: nil, screenshotBase64: "img1")
        XCTAssertTrue(first, "First screen should be accepted")

        let second = session.capture(
            elements: screenB, hints: [], actionType: "swipe",
            arrivedVia: "up", screenshotBase64: "img2")
        XCTAssertFalse(second,
            "Scrolled view with 80%+ overlap should be rejected as duplicate")
        XCTAssertEqual(session.screenCount, 1)
    }

    func testPartialOverlapBelowThresholdAccepted() {
        // <80% overlap simulates a real navigation change — should be accepted
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test scroll accept")

        let screenA = [
            TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98),
            TapPoint(text: "General", tapX: 205, tapY: 200, confidence: 0.95),
            TapPoint(text: "Privacy", tapX: 205, tapY: 280, confidence: 0.93),
        ]
        let screenB = [
            TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98),
            TapPoint(text: "General", tapX: 205, tapY: 200, confidence: 0.95),
            TapPoint(text: "About", tapX: 205, tapY: 280, confidence: 0.92),
        ]

        session.capture(
            elements: screenA, hints: [], actionType: nil,
            arrivedVia: nil, screenshotBase64: "img1")

        // Jaccard = 2/4 = 0.5, below 0.8 threshold
        let second = session.capture(
            elements: screenB, hints: [], actionType: "tap",
            arrivedVia: "About", screenshotBase64: "img2")
        XCTAssertTrue(second,
            "50% overlap should be below threshold and accepted as new screen")
        XCTAssertEqual(session.screenCount, 2)
    }

    // MARK: - Mode Detection

    func testGoalDrivenMode() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "check version")
        XCTAssertEqual(session.currentMode, .goalDriven,
            "Non-empty goal should set goal-driven mode")
    }

    func testDiscoveryMode() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "")
        XCTAssertEqual(session.currentMode, .discovery,
            "Empty goal should set discovery mode")
    }

    func testManifestModeIsGoalDriven() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "", goals: ["check version", "change brightness"])
        XCTAssertEqual(session.currentMode, .goalDriven,
            "Manifest mode with goals should be goal-driven")
        XCTAssertEqual(session.currentGoal, "check version",
            "First goal in manifest should be current")
    }

    // MARK: - Action History

    func testActionLogTracksAcceptedCaptures() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test")

        session.capture(
            elements: [TapPoint(text: "General", tapX: 205, tapY: 250, confidence: 0.95)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img1")

        let actions = session.actions
        XCTAssertEqual(actions.count, 1)
        XCTAssertFalse(actions[0].wasDuplicate)
    }

    func testActionLogTracksDuplicateRejections() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test")

        let elements = [TapPoint(text: "General", tapX: 205, tapY: 250, confidence: 0.95)]

        session.capture(elements: elements, hints: [], actionType: nil,
            arrivedVia: nil, screenshotBase64: "img1")
        session.capture(elements: elements, hints: [], actionType: "tap",
            arrivedVia: "General", screenshotBase64: "img2")

        let actions = session.actions
        XCTAssertEqual(actions.count, 2)
        XCTAssertFalse(actions[0].wasDuplicate, "First capture should not be duplicate")
        XCTAssertTrue(actions[1].wasDuplicate, "Second capture of same screen should be duplicate")
    }

    // MARK: - Start Screen Elements

    func testStartScreenElementsSetOnFirstCapture() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test")

        XCTAssertNil(session.startScreenElements, "No start elements before first capture")

        let elements = [TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98)]
        session.capture(elements: elements, hints: [], actionType: nil,
            arrivedVia: nil, screenshotBase64: "img1")

        XCTAssertNotNil(session.startScreenElements)
        XCTAssertEqual(session.startScreenElements?.first?.text, "Settings")
    }

    func testStartScreenElementsNotOverwrittenOnSecondCapture() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test")

        session.capture(
            elements: [TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img1")
        session.capture(
            elements: [TapPoint(text: "About", tapX: 205, tapY: 120, confidence: 0.96)],
            hints: [], actionType: "tap", arrivedVia: "About", screenshotBase64: "img2")

        XCTAssertEqual(session.startScreenElements?.first?.text, "Settings",
            "Start elements should remain from first capture")
    }

    // MARK: - Manifest Mode / Goals Queue

    func testManifestFinalizeAdvancesToNextGoal() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "",
            goals: ["check version", "change brightness", "enable dark mode"])

        XCTAssertEqual(session.currentGoal, "check version")
        XCTAssertEqual(session.totalGoals, 3)
        XCTAssertTrue(session.hasMoreGoals)
        XCTAssertEqual(session.remainingGoals, ["change brightness", "enable dark mode"])

        // Capture a screen for goal 1
        session.capture(
            elements: [TapPoint(text: "Version", tapX: 205, tapY: 300, confidence: 0.9)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img1")

        // Finalize goal 1 — should auto-advance
        let data1 = session.finalize()
        XCTAssertNotNil(data1)
        XCTAssertEqual(data1?.goal, "check version")
        XCTAssertTrue(session.active, "Session should still be active with more goals")
        XCTAssertEqual(session.currentGoal, "change brightness")
        XCTAssertEqual(session.screenCount, 0, "Screens should be reset for next goal")
        XCTAssertTrue(session.hasMoreGoals)
        XCTAssertEqual(session.remainingGoals, ["enable dark mode"])

        // Capture for goal 2
        session.capture(
            elements: [TapPoint(text: "Brightness", tapX: 205, tapY: 300, confidence: 0.9)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img2")

        // Finalize goal 2 — still one more
        let data2 = session.finalize()
        XCTAssertNotNil(data2)
        XCTAssertEqual(data2?.goal, "change brightness")
        XCTAssertTrue(session.active)
        XCTAssertEqual(session.currentGoal, "enable dark mode")
        XCTAssertFalse(session.hasMoreGoals)
        XCTAssertTrue(session.remainingGoals.isEmpty)

        // Capture for goal 3
        session.capture(
            elements: [TapPoint(text: "Dark Mode", tapX: 205, tapY: 300, confidence: 0.9)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img3")

        // Finalize goal 3 — session should fully deactivate
        let data3 = session.finalize()
        XCTAssertNotNil(data3)
        XCTAssertEqual(data3?.goal, "enable dark mode")
        XCTAssertFalse(session.active, "Session should be inactive after last goal")
        XCTAssertEqual(session.currentGoal, "")
    }

    func testSingleGoalFinalizeDeactivates() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "check version")

        XCTAssertFalse(session.hasMoreGoals)
        XCTAssertEqual(session.totalGoals, 0)

        session.capture(
            elements: [TapPoint(text: "Version", tapX: 205, tapY: 300, confidence: 0.9)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img")

        let data = session.finalize()
        XCTAssertNotNil(data)
        XCTAssertFalse(session.active, "Single-goal session should deactivate on finalize")
    }

    func testManifestActionLogResetsPerGoal() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "",
            goals: ["goal1", "goal2"])

        session.capture(
            elements: [TapPoint(text: "Screen1", tapX: 205, tapY: 250, confidence: 0.9)],
            hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img1")

        XCTAssertEqual(session.actions.count, 1)

        // Finalize goal 1
        _ = session.finalize()

        // Action log should be reset for goal 2
        XCTAssertTrue(session.actions.isEmpty,
            "Action log should reset when advancing to next goal")
    }

    // MARK: - NavigationGraph Integration

    func testGraphPopulatedOnCapture() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test graph")

        session.capture(
            elements: [TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95)],
            hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img1"
        )

        XCTAssertTrue(session.currentGraph.started,
            "Graph should be started after first capture")
        XCTAssertEqual(session.currentGraph.nodeCount, 1)
    }

    func testGraphRecordsTransitions() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test graph")

        session.capture(
            elements: [TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95)],
            hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img1"
        )
        session.capture(
            elements: [TapPoint(text: "About", tapX: 205, tapY: 200, confidence: 0.92)],
            hints: [], icons: [],
            actionType: "tap", arrivedVia: "General", screenshotBase64: "img2"
        )

        XCTAssertEqual(session.currentGraph.nodeCount, 2)
        XCTAssertEqual(session.currentGraph.edgeCount, 1)
    }

    func testFinalizeIncludesGraphSnapshot() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test graph")

        session.capture(
            elements: [TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95)],
            hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img1"
        )
        session.capture(
            elements: [TapPoint(text: "About", tapX: 205, tapY: 200, confidence: 0.92)],
            hints: [], icons: [],
            actionType: "tap", arrivedVia: "General", screenshotBase64: "img2"
        )

        let data = session.finalize()
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.graphSnapshot.nodes.count, 2)
        XCTAssertEqual(data?.graphSnapshot.edges.count, 1)
        XCTAssertFalse(data?.graphSnapshot.rootFingerprint.isEmpty ?? true)
    }

    func testGraphResetsOnManifestGoalAdvance() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "", goals: ["goal1", "goal2"])

        session.capture(
            elements: [TapPoint(text: "Screen1", tapX: 205, tapY: 250, confidence: 0.9)],
            hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img1"
        )

        let data = session.finalize()
        XCTAssertNotNil(data)
        XCTAssertEqual(data?.graphSnapshot.nodes.count, 1)

        // Graph should be reset for next goal
        XCTAssertFalse(session.currentGraph.started,
            "Graph should be reset when advancing to next goal")
    }

    func testGraphWithIcons() {
        let session = ExplorationSession()
        session.start(appName: "Settings", goal: "test icons")

        let icons = [
            IconDetector.DetectedIcon(tapX: 56, tapY: 850, estimatedSize: 24),
            IconDetector.DetectedIcon(tapX: 158, tapY: 850, estimatedSize: 24),
        ]
        session.capture(
            elements: [TapPoint(text: "Home", tapX: 205, tapY: 200, confidence: 0.95)],
            hints: [], icons: icons,
            actionType: nil, arrivedVia: nil, screenshotBase64: "img1"
        )

        let fp = session.currentGraph.currentFingerprint
        let node = session.currentGraph.node(for: fp)
        XCTAssertEqual(node?.icons.count, 2,
            "Icons should be stored in graph node")
    }
}
