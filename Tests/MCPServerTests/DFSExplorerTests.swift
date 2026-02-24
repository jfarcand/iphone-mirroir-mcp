// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for DFSExplorer: autonomous DFS exploration with budget limits and backtracking.
// ABOUTME: Uses mock ScreenDescribing and InputProviding to simulate app navigation.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class DFSExplorerTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeElements(_ texts: [String], startY: Double = 120) -> [TapPoint] {
        texts.enumerated().map { (i, text) in
            TapPoint(text: text, tapX: 205, tapY: startY + Double(i) * 80, confidence: 0.95)
        }
    }

    /// Mock screen describer that returns a sequence of pre-defined screens.
    /// Each call to describe() returns the next screen in the sequence.
    final class MockDescriber: ScreenDescribing, @unchecked Sendable {
        private var screens: [ScreenDescriber.DescribeResult]
        private var index = 0
        private let lock = NSLock()

        init(screens: [ScreenDescriber.DescribeResult]) {
            self.screens = screens
        }

        func describe(skipOCR: Bool) -> ScreenDescriber.DescribeResult? {
            lock.lock()
            defer { lock.unlock() }
            guard index < screens.count else {
                // Return last screen if exhausted (for repeated OCR calls)
                return screens.last
            }
            let result = screens[index]
            index += 1
            return result
        }

        /// Reset the index to replay the sequence.
        func reset() {
            lock.lock()
            defer { lock.unlock() }
            index = 0
        }

        /// Number of describe() calls made so far.
        var callCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return index
        }
    }

    /// Mock input provider that records actions without performing them.
    final class MockInput: InputProviding, @unchecked Sendable {
        private var tapLog: [(x: Double, y: Double)] = []
        private var keyLog: [(key: String, modifiers: [String])] = []
        private var swipeLog: [(fromX: Double, fromY: Double, toX: Double, toY: Double)] = []
        private let lock = NSLock()

        func tap(x: Double, y: Double, cursorMode: CursorMode?) -> String? {
            lock.lock()
            defer { lock.unlock() }
            tapLog.append((x: x, y: y))
            return nil
        }

        func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double,
                   durationMs: Int, cursorMode: CursorMode?) -> String? {
            lock.lock()
            defer { lock.unlock() }
            swipeLog.append((fromX: fromX, fromY: fromY, toX: toX, toY: toY))
            return nil
        }

        func drag(fromX: Double, fromY: Double, toX: Double, toY: Double,
                  durationMs: Int, cursorMode: CursorMode?) -> String? { nil }
        func longPress(x: Double, y: Double, durationMs: Int, cursorMode: CursorMode?) -> String? { nil }
        func doubleTap(x: Double, y: Double, cursorMode: CursorMode?) -> String? { nil }
        func shake() -> TypeResult { TypeResult(success: true, warning: nil, error: nil) }
        func typeText(_ text: String) -> TypeResult { TypeResult(success: true, warning: nil, error: nil) }

        func pressKey(keyName: String, modifiers: [String]) -> TypeResult {
            lock.lock()
            defer { lock.unlock() }
            keyLog.append((key: keyName, modifiers: modifiers))
            return TypeResult(success: true, warning: nil, error: nil)
        }

        func launchApp(name: String) -> String? { nil }
        func openURL(_ url: String) -> String? { nil }

        var taps: [(x: Double, y: Double)] {
            lock.lock()
            defer { lock.unlock() }
            return tapLog
        }

        var keys: [(key: String, modifiers: [String])] {
            lock.lock()
            defer { lock.unlock() }
            return keyLog
        }
    }

    // MARK: - Budget Exhaustion

    func testExplorerFinishesWhenBudgetExhausted() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General", "About", "Privacy"])
        let rootScreen = ScreenDescriber.DescribeResult(
            elements: rootElements, screenshotBase64: "img0"
        )

        // Capture root screen in session
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Budget allows only 1 screen — explorer should finish immediately
        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 1, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 3,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let describer = MockDescriber(screens: [rootScreen])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        if case .finished = result {
            // Expected: budget exhausted (maxScreens=1, already have 1)
        } else {
            XCTFail("Expected .finished when budget exhausted, got \(result)")
        }
    }

    func testExplorerFinishesWhenTimeExhausted() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Budget with 0 seconds — immediately exhausted
        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 0,
            maxActionsPerScreen: 5, scrollLimit: 3,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        if case .finished = result {
            // Expected
        } else {
            XCTFail("Expected .finished when time exhausted, got \(result)")
        }
    }

    // MARK: - Tap and Navigate

    func testExplorerTapsUnvisitedElement() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General", "About"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 3,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let afterTapElements = makeElements(["Version Info", "Build Number"])
        let describer = MockDescriber(screens: [
            // First: OCR of current screen (root)
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            // Second: OCR after tap
            ScreenDescriber.DescribeResult(elements: afterTapElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        if case .continue(let desc) = result {
            XCTAssertTrue(desc.contains("new screen") || desc.contains("Tapped"),
                "Should describe the tap action. Got: \(desc)")
        } else {
            XCTFail("Expected .continue after tapping, got \(result)")
        }

        // Verify a tap was performed
        XCTAssertEqual(input.taps.count, 1, "Should have tapped one element")
    }

    // MARK: - Backtrack

    func testExplorerBacktracksWhenNoUnvisitedElements() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Root with just one navigable element
        let rootElements = makeElements(["Settings"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 3,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Step 1: Tap "Settings" → navigate to detail
        let detailElements = makeElements(["Version", "Build"])
        let describer1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        let step1 = explorer.step(
            describer: describer1, input: input, strategy: MobileAppStrategy.self
        )

        if case .continue = step1 {
            // Expected: tapped "Settings", reached detail screen
        } else {
            XCTFail("Expected .continue for step 1, got \(step1)")
        }

        // Step 2: Detail screen has elements but after we tap them all or
        // the graph sees all visited, it should backtrack.
        // Mark all detail elements as visited so backtrack triggers.
        let graph = session.currentGraph
        let currentFP = graph.currentFingerprint
        graph.markElementVisited(fingerprint: currentFP, elementText: "Version")
        graph.markElementVisited(fingerprint: currentFP, elementText: "Build")

        let describer2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])

        let step2 = explorer.step(
            describer: describer2, input: input, strategy: MobileAppStrategy.self
        )

        // Should backtrack since all elements on detail are visited
        if case .backtracked = step2 {
            // Expected
        } else if case .finished = step2 {
            // Also acceptable if explorer decides exploration is done
        } else {
            XCTFail("Expected .backtracked or .finished, got \(step2)")
        }
    }

    // MARK: - Completed State

    func testExplorerCompletedInitiallyFalse() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "")

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)

        XCTAssertFalse(explorer.completed, "Explorer should not be completed initially")
    }

    func testExplorerStatsTrackProgress() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let stats = explorer.stats
        XCTAssertEqual(stats.nodeCount, 1, "Should have 1 node from initial capture")
        XCTAssertEqual(stats.actionCount, 0, "No actions taken yet")
        XCTAssertGreaterThanOrEqual(stats.elapsedSeconds, 0)
    }

    // MARK: - OCR Failure

    func testExplorerPausesOnOCRFailure() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Describer that returns nil (simulating OCR failure)
        let describer = MockDescriber(screens: [])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        if case .paused(let reason) = result {
            XCTAssertTrue(reason.contains("Failed"),
                "Pause reason should mention failure. Got: \(reason)")
        } else {
            XCTFail("Expected .paused on OCR failure, got \(result)")
        }
    }

    // MARK: - Root-Only Exploration

    func testExplorerFinishesAtRootWhenAllVisited() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Root screen with short elements that will be filtered by MobileAppStrategy
        // (landmarkMinLength = 3, so "Go" would be too short)
        let rootElements = makeElements(["AB"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Mark the only element as visited
        let graph = session.currentGraph
        graph.markElementVisited(fingerprint: graph.currentFingerprint, elementText: "AB")

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        // At root with no unvisited elements and stack depth 1 → finished
        if case .finished = result {
            // Expected
        } else {
            XCTFail("Expected .finished at root with all elements visited, got \(result)")
        }
    }

    // MARK: - Skip Patterns

    func testExplorerSkipsDangerousElements() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Only navigable element is "Sign Out" which should be skipped
        let rootElements = makeElements(["Sign Out"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        // "Sign Out" should be skipped, no elements to tap → backtrack at root → finished
        if case .finished = result {
            // Expected
        } else {
            XCTFail("Expected .finished when only element is skippable, got \(result)")
        }

        XCTAssertEqual(input.taps.count, 0, "Should not tap dangerous elements")
    }

    // MARK: - Alert Recovery

    func testExplorerDismissesAlertBeforeExploring() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General", "About"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // First OCR returns an alert, second returns clean screen after dismiss
        let alertElements: [TapPoint] = [
            TapPoint(text: "\"App\" would like to use your location", tapX: 205, tapY: 300, confidence: 0.95),
            TapPoint(text: "Allow", tapX: 205, tapY: 420, confidence: 0.95),
            TapPoint(text: "Don't Allow", tapX: 205, tapY: 480, confidence: 0.95),
        ]
        let afterTapElements = makeElements(["Version Info", "Build Number"])

        let describer = MockDescriber(screens: [
            // step() calls dismissAlertIfPresent: first OCR → alert
            ScreenDescriber.DescribeResult(elements: alertElements, screenshotBase64: "alert_img"),
            // After tapping dismiss → clean root screen
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            // performTap: after-tap OCR
            ScreenDescriber.DescribeResult(elements: afterTapElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        // Should have tapped "Don't Allow" to dismiss alert, then continued exploring
        if case .continue = result {
            // Expected: explored after dismissing alert
        } else {
            XCTFail("Expected .continue after dismissing alert, got \(result)")
        }

        // First tap should be the dismiss (Don't Allow), second is the exploration tap
        XCTAssertGreaterThanOrEqual(input.taps.count, 2,
            "Should tap dismiss target + exploration target")
    }

    func testExplorerAlertDoesNotCreateGraphEdge() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let alertElements: [TapPoint] = [
            TapPoint(text: "Rate this app", tapX: 205, tapY: 300, confidence: 0.95),
            TapPoint(text: "Not Now", tapX: 205, tapY: 420, confidence: 0.95),
            TapPoint(text: "OK", tapX: 205, tapY: 480, confidence: 0.95),
        ]
        let afterTapElements = makeElements(["Version Info", "Build Number"])

        let describer = MockDescriber(screens: [
            // Alert detected on initial OCR
            ScreenDescriber.DescribeResult(elements: alertElements, screenshotBase64: "alert_img"),
            // After dismiss → root
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            // After exploration tap → new screen
            ScreenDescriber.DescribeResult(elements: afterTapElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        _ = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        let graph = session.currentGraph
        // The graph should have 2 nodes (root + tapped destination), not 3
        // The alert should not have been recorded as a screen
        XCTAssertLessThanOrEqual(graph.nodeCount, 2,
            "Alert should not create a graph node")
    }

    // MARK: - Depth Limit

    func testExplorerRespectsMaxDepth() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Budget with maxDepth=1 — can only go one level deep
        let budget = ExplorationBudget(
            maxDepth: 1, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 3,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Step 1: Tap to navigate one level deep
        let deepElements = makeElements(["About", "Version"])
        let describer1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: deepElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        let step1 = explorer.step(
            describer: describer1, input: input, strategy: MobileAppStrategy.self
        )

        if case .continue = step1 {
            // Expected: navigated one level
        } else {
            XCTFail("Expected .continue for first step, got \(step1)")
        }

        // Step 2: At depth 1 with maxDepth=1, elements should be terminal
        // MobileAppStrategy.isTerminal checks depth >= budget.maxDepth
        let describer2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: deepElements, screenshotBase64: "img1"),
        ])

        // Mark elements visited so it backtracks
        let graph = session.currentGraph
        let fp = graph.currentFingerprint
        for el in deepElements {
            graph.markElementVisited(fingerprint: fp, elementText: el.text)
        }

        let step2 = explorer.step(
            describer: describer2, input: input, strategy: MobileAppStrategy.self
        )

        // Should backtrack since all visited at depth limit
        if case .backtracked = step2 {
            // Expected
        } else if case .finished = step2 {
            // Also acceptable
        } else {
            XCTFail("Expected .backtracked or .finished at depth limit, got \(step2)")
        }
    }
}
