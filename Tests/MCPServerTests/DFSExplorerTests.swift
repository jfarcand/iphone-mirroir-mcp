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

        var swipes: [(fromX: Double, fromY: Double, toX: Double, toY: Double)] {
            lock.lock()
            defer { lock.unlock() }
            return swipeLog
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

    // MARK: - Scroll Handling

    func testExplorerScrollsBeforeBacktracking() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

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

        // Mark root element visited so explorer would normally backtrack
        let graph = session.currentGraph
        graph.markElementVisited(fingerprint: graph.currentFingerprint, elementText: "Settings")

        // After scroll, new elements appear
        let scrolledElements = makeElements(["General", "Privacy", "About"])
        let describer = MockDescriber(screens: [
            // step() OCR: all visited on root
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            // After scroll: new elements visible
            ScreenDescriber.DescribeResult(elements: scrolledElements, screenshotBase64: "img0_scrolled"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        if case .continue(let desc) = result {
            XCTAssertTrue(desc.contains("Scrolled"), "Should describe scroll action. Got: \(desc)")
        } else {
            XCTFail("Expected .continue after scroll, got \(result)")
        }
    }

    func testExplorerRespectsScrollLimit() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Budget allows 0 scrolls
        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Mark all visited
        let graph = session.currentGraph
        graph.markElementVisited(fingerprint: graph.currentFingerprint, elementText: "Settings")

        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        // With scrollLimit=0 and at root, should finish (not scroll)
        if case .finished = result {
            // Expected: no scrolling, immediate finish
        } else {
            XCTFail("Expected .finished with scrollLimit=0, got \(result)")
        }
    }

    func testExplorerScrollExhaustionFallsToBacktrack() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 1,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Navigate to a detail screen
        let detailElements = makeElements(["Version", "Build"])
        let describer1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        // Step 1: Tap to get to detail screen
        _ = explorer.step(describer: describer1, input: input, strategy: MobileAppStrategy.self)

        // Mark all detail elements visited
        let graph = session.currentGraph
        let fp = graph.currentFingerprint
        graph.markElementVisited(fingerprint: fp, elementText: "Version")
        graph.markElementVisited(fingerprint: fp, elementText: "Build")

        // Scroll returns same elements (no novel ones)
        let describer2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
            // After scroll: same elements
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])

        let result = explorer.step(
            describer: describer2, input: input, strategy: MobileAppStrategy.self
        )

        // Should backtrack after scroll found nothing new
        if case .backtracked = result {
            // Expected
        } else if case .finished = result {
            // Also acceptable
        } else {
            XCTFail("Expected .backtracked after scroll exhaustion, got \(result)")
        }
    }

    // MARK: - Tab Bar Fast-Backtrack

    func testFastBacktrackTriggersOnDeepTabApp() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Root is a tab bar screen with multiple tabs
        let rootElements: [TapPoint] = [
            TapPoint(text: "Home", tapX: 56, tapY: 850, confidence: 0.95),
            TapPoint(text: "Search", tapX: 158, tapY: 850, confidence: 0.95),
            TapPoint(text: "Profile", tapX: 260, tapY: 850, confidence: 0.95),
            TapPoint(text: "Featured", tapX: 205, tapY: 200, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Navigate deep: root -> level1 -> level2 -> level3
        let level1 = makeElements(["Section A", "Item 1"])
        let level2 = makeElements(["Detail X", "Info"])
        let level3 = makeElements(["Deep Data", "Value"])

        // Step 1: root -> level1
        let desc1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: level1, screenshotBase64: "img1"),
        ])
        let input = MockInput()
        _ = explorer.step(describer: desc1, input: input, strategy: MobileAppStrategy.self)

        // Step 2: level1 -> level2
        let desc2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: level1, screenshotBase64: "img1"),
            ScreenDescriber.DescribeResult(elements: level2, screenshotBase64: "img2"),
        ])
        _ = explorer.step(describer: desc2, input: input, strategy: MobileAppStrategy.self)

        // Step 3: level2 -> level3
        let desc3 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: level2, screenshotBase64: "img2"),
            ScreenDescriber.DescribeResult(elements: level3, screenshotBase64: "img3"),
        ])
        _ = explorer.step(describer: desc3, input: input, strategy: MobileAppStrategy.self)

        // Mark all level3 elements as visited to trigger backtrack
        let graph = session.currentGraph
        let fp = graph.currentFingerprint
        for el in level3 { graph.markElementVisited(fingerprint: fp, elementText: el.text) }

        // Step 4: Should fast-backtrack to root (3 levels in one step)
        let desc4 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: level3, screenshotBase64: "img3"),
        ])

        let result = explorer.step(
            describer: desc4, input: input, strategy: MobileAppStrategy.self
        )

        if case .backtracked = result {
            // Should have swiped back multiple times for fast backtrack
            let backSwipes = input.swipes.filter { $0.fromX < 20 && $0.toX > 200 }
            XCTAssertEqual(backSwipes.count, 3,
                "Fast backtrack from depth 3 should swipe back 3 times")
        } else {
            XCTFail("Expected .backtracked for fast backtrack, got \(result)")
        }
    }

    func testFastBacktrackDoesNotTriggerForShallowStack() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Root is tabRoot
        let rootElements: [TapPoint] = [
            TapPoint(text: "Home", tapX: 56, tapY: 850, confidence: 0.95),
            TapPoint(text: "Search", tapX: 158, tapY: 850, confidence: 0.95),
            TapPoint(text: "Profile", tapX: 260, tapY: 850, confidence: 0.95),
            TapPoint(text: "Featured", tapX: 205, tapY: 200, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Disable scouting so tab root navigates directly (this test is about backtrack behavior)
        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 0,
            maxScoutsPerScreen: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Navigate just one level deep (stackDepth=2, which is <= 2)
        let level1 = makeElements(["Detail Info", "Back"])
        let desc1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: level1, screenshotBase64: "img1"),
        ])
        let input = MockInput()
        _ = explorer.step(describer: desc1, input: input, strategy: MobileAppStrategy.self)

        // Mark all visited to trigger backtrack
        let graph = session.currentGraph
        let fp = graph.currentFingerprint
        for el in level1 { graph.markElementVisited(fingerprint: fp, elementText: el.text) }

        let desc2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: level1, screenshotBase64: "img1"),
        ])

        let result = explorer.step(
            describer: desc2, input: input, strategy: MobileAppStrategy.self
        )

        if case .backtracked = result {
            // Normal single-step backtrack, not fast
            let backSwipes = input.swipes.filter { $0.fromX < 20 && $0.toX > 200 }
            // Should be 1 (normal backtrack) not multiple (fast backtrack)
            XCTAssertEqual(backSwipes.count, 1,
                "Shallow stack should use normal backtrack (1 swipe)")
        } else {
            XCTFail("Expected .backtracked, got \(result)")
        }
    }

    func testFastBacktrackDoesNotTriggerForNonTabApp() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Root is settings (not tabRoot)
        let rootElements = makeElements(["Settings", "General", "Privacy"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Navigate 3 levels deep
        let l1 = makeElements(["Section A", "Item 1"])
        let l2 = makeElements(["Detail X", "Info"])
        let l3 = makeElements(["Deep Val", "Data"])

        let desc1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: l1, screenshotBase64: "img1"),
        ])
        let input = MockInput()
        _ = explorer.step(describer: desc1, input: input, strategy: MobileAppStrategy.self)

        let desc2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: l1, screenshotBase64: "img1"),
            ScreenDescriber.DescribeResult(elements: l2, screenshotBase64: "img2"),
        ])
        _ = explorer.step(describer: desc2, input: input, strategy: MobileAppStrategy.self)

        let desc3 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: l2, screenshotBase64: "img2"),
            ScreenDescriber.DescribeResult(elements: l3, screenshotBase64: "img3"),
        ])
        _ = explorer.step(describer: desc3, input: input, strategy: MobileAppStrategy.self)

        // Mark all l3 visited
        let graph = session.currentGraph
        let fp = graph.currentFingerprint
        for el in l3 { graph.markElementVisited(fingerprint: fp, elementText: el.text) }

        let swipesBefore = input.swipes.count
        let desc4 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: l3, screenshotBase64: "img3"),
        ])
        _ = explorer.step(describer: desc4, input: input, strategy: MobileAppStrategy.self)

        // Non-tab app: should do normal single backtrack, not fast
        let newBackSwipes = input.swipes.dropFirst(swipesBefore)
        let leftEdgeSwipes = newBackSwipes.filter { $0.fromX < 20 && $0.toX > 200 }
        XCTAssertEqual(leftEdgeSwipes.count, 1,
            "Non-tab app should use single backtrack")
    }

    // MARK: - Backtrack Fingerprint Sync

    func testExplorerExploresParentAfterBacktracking() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Root has two navigable elements
        let rootElements = makeElements(["General", "Privacy"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Step 1: Tap "General" → navigate to detail
        let detailElements = makeElements(["About", "Version"])
        let desc1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()
        let step1 = explorer.step(describer: desc1, input: input, strategy: MobileAppStrategy.self)
        guard case .continue = step1 else {
            XCTFail("Expected .continue for step 1, got \(step1)")
            return
        }

        // Mark all detail elements visited to trigger backtrack
        let graph = session.currentGraph
        let detailFP = graph.currentFingerprint
        graph.markElementVisited(fingerprint: detailFP, elementText: "About")
        graph.markElementVisited(fingerprint: detailFP, elementText: "Version")

        // Step 2: All visited on detail → backtrack to root
        let desc2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])
        let step2 = explorer.step(describer: desc2, input: input, strategy: MobileAppStrategy.self)
        guard case .backtracked = step2 else {
            XCTFail("Expected .backtracked for step 2, got \(step2)")
            return
        }

        // Step 3: After backtracking to root, explorer should tap "Privacy" (still unvisited)
        let privacyDetail = makeElements(["Location", "Tracking"])
        let desc3 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: privacyDetail, screenshotBase64: "img2"),
        ])
        let step3 = explorer.step(describer: desc3, input: input, strategy: MobileAppStrategy.self)

        // Should continue exploring, NOT finish prematurely
        if case .continue(let desc) = step3 {
            XCTAssertTrue(desc.contains("Privacy") || desc.contains("new screen"),
                "Should tap 'Privacy' on root after backtrack. Got: \(desc)")
        } else {
            XCTFail("Expected .continue after backtrack to root with unvisited elements, got \(step3)")
        }
    }

    // MARK: - Punctuation-Only Filter

    func testPunctuationOnlyElementsFiltered() {
        XCTAssertTrue(LandmarkPicker.isPunctuationOnly("..."))
        XCTAssertTrue(LandmarkPicker.isPunctuationOnly("+++"))
        XCTAssertTrue(LandmarkPicker.isPunctuationOnly("•••"))
        XCTAssertTrue(LandmarkPicker.isPunctuationOnly("→"))
        XCTAssertTrue(LandmarkPicker.isPunctuationOnly("---"))
        XCTAssertFalse(LandmarkPicker.isPunctuationOnly("OK"))
        XCTAssertFalse(LandmarkPicker.isPunctuationOnly("More..."))
        XCTAssertFalse(LandmarkPicker.isPunctuationOnly("General"))
        XCTAssertFalse(LandmarkPicker.isPunctuationOnly("1+1"))
    }

    // MARK: - Scout Phase

    func testExplorerScoutsBeforeDiving() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Settings-style screen with enough navigation elements to trigger scouting
        // Each label is paired with ">" on the same Y to classify as navigation
        let rootElements: [TapPoint] = [
            TapPoint(text: "General", tapX: 100, tapY: 200, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 200, confidence: 0.95),
            TapPoint(text: "Privacy", tapX: 100, tapY: 280, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 280, confidence: 0.95),
            TapPoint(text: "Display", tapX: 100, tapY: 360, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 360, confidence: 0.95),
            TapPoint(text: "Storage", tapX: 100, tapY: 440, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 440, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 10, scrollLimit: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // After tapping "General", we arrive at a new screen
        let detailElements = makeElements(["About Phone", "iOS Version"])
        let describer = MockDescriber(screens: [
            // step() OCR: root screen
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            // After scout tap: new screen
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        if case .continue(let desc) = result {
            XCTAssertTrue(desc.contains("Scouted"),
                "First action on a scoutable screen should be a scout. Got: \(desc)")
        } else {
            XCTFail("Expected .continue with scout, got \(result)")
        }

        // Should have tapped once + swiped back once (scout backtrack)
        XCTAssertEqual(input.taps.count, 1, "Scout should tap the element")
        let backSwipes = input.swipes.filter { $0.fromX < 20 }
        XCTAssertEqual(backSwipes.count, 1, "Scout should swipe back immediately")
    }

    func testExplorerAdvancesToDiveAfterScouting() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Minimal scoutable screen: 4 navigation elements
        let rootElements: [TapPoint] = [
            TapPoint(text: "Item A", tapX: 100, tapY: 200, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 200, confidence: 0.95),
            TapPoint(text: "Item B", tapX: 100, tapY: 280, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 280, confidence: 0.95),
            TapPoint(text: "Item C", tapX: 100, tapY: 360, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 360, confidence: 0.95),
            TapPoint(text: "Item D", tapX: 100, tapY: 440, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 440, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Use maxScoutsPerScreen: 2 to force early transition to dive
        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 10, scrollLimit: 0,
            maxScoutsPerScreen: 2,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let input = MockInput()
        let detailScreen = ScreenDescriber.DescribeResult(
            elements: makeElements(["Detail Info"]), screenshotBase64: "img_detail"
        )

        // Scout 1: Item A navigates
        let desc1 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            detailScreen,
        ])
        let step1 = explorer.step(describer: desc1, input: input, strategy: MobileAppStrategy.self)
        if case .continue(let desc) = step1 {
            XCTAssertTrue(desc.contains("Scouted"), "Step 1 should scout. Got: \(desc)")
        }

        // Scout 2: Item B navigates (maxScoutsPerScreen reached after this)
        let desc2 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            detailScreen,
        ])
        let step2 = explorer.step(describer: desc2, input: input, strategy: MobileAppStrategy.self)
        if case .continue(let desc) = step2 {
            XCTAssertTrue(desc.contains("Scouted"), "Step 2 should scout. Got: \(desc)")
        }

        // Step 3: Should now be in dive phase (maxScoutsPerScreen=2 reached)
        let diveDetail = makeElements(["Dive Content", "More Info"])
        let desc3 = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: diveDetail, screenshotBase64: "img_dive"),
        ])
        let step3 = explorer.step(describer: desc3, input: input, strategy: MobileAppStrategy.self)
        if case .continue(let desc) = step3 {
            XCTAssertTrue(desc.contains("Tapped"),
                "Step 3 should dive (normal tap). Got: \(desc)")
        } else {
            XCTFail("Expected .continue for dive step, got \(step3)")
        }
    }

    func testExplorerSkipsScoutOnDetailScreen() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Detail screen: has back button + few navigable elements (<4 triggers detail classification)
        let rootElements = makeElements(["About", "Version"])
        session.capture(
            elements: rootElements,
            hints: ["Back navigation detected"],
            icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let afterTap = makeElements(["Build Number", "Serial"])
        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(
                elements: rootElements, hints: ["Back navigation detected"],
                screenshotBase64: "img0"
            ),
            ScreenDescriber.DescribeResult(elements: afterTap, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        let result = explorer.step(
            describer: describer, input: input, strategy: MobileAppStrategy.self
        )

        // Detail screens should NOT scout — should directly tap (dive behavior)
        if case .continue(let desc) = result {
            XCTAssertTrue(desc.contains("Tapped"),
                "Detail screen should dive directly, not scout. Got: \(desc)")
        } else {
            XCTFail("Expected .continue, got \(result)")
        }
    }

    func testScoutRecordsNavigatedResult() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements: [TapPoint] = [
            TapPoint(text: "General", tapX: 100, tapY: 200, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 200, confidence: 0.95),
            TapPoint(text: "Privacy", tapX: 100, tapY: 280, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 280, confidence: 0.95),
            TapPoint(text: "Display", tapX: 100, tapY: 360, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 360, confidence: 0.95),
            TapPoint(text: "Storage", tapX: 100, tapY: 440, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 440, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // After scout tap → new screen (different elements = different fingerprint)
        let newScreen = makeElements(["About Phone", "Model Name"])
        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: newScreen, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        _ = explorer.step(describer: describer, input: input, strategy: MobileAppStrategy.self)

        // Check that the graph recorded a scout result
        let graph = session.currentGraph
        let rootFP = graph.rootFingerprint
        let results = graph.scoutResults(for: rootFP)
        XCTAssertEqual(results["General"], .navigated,
            "Scout should record .navigated for element that changed the screen")
    }

    func testScoutRecordsNoChangeResult() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements: [TapPoint] = [
            TapPoint(text: "General", tapX: 100, tapY: 200, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 200, confidence: 0.95),
            TapPoint(text: "Privacy", tapX: 100, tapY: 280, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 280, confidence: 0.95),
            TapPoint(text: "Display", tapX: 100, tapY: 360, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 360, confidence: 0.95),
            TapPoint(text: "Storage", tapX: 100, tapY: 440, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 440, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // After scout tap → same screen (same elements = same fingerprint)
        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
        ])
        let input = MockInput()

        _ = explorer.step(describer: describer, input: input, strategy: MobileAppStrategy.self)

        let graph = session.currentGraph
        let rootFP = graph.rootFingerprint
        let results = graph.scoutResults(for: rootFP)
        XCTAssertEqual(results["General"], .noChange,
            "Scout should record .noChange for element that didn't change screen")
    }

    func testScoutBacktracksImmediatelyAfterNavigation() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements: [TapPoint] = [
            TapPoint(text: "General", tapX: 100, tapY: 200, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 200, confidence: 0.95),
            TapPoint(text: "Privacy", tapX: 100, tapY: 280, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 280, confidence: 0.95),
            TapPoint(text: "Display", tapX: 100, tapY: 360, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 360, confidence: 0.95),
            TapPoint(text: "Storage", tapX: 100, tapY: 440, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 440, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget.default
        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let newScreen = makeElements(["Detail View", "Content"])
        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: newScreen, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        _ = explorer.step(describer: describer, input: input, strategy: MobileAppStrategy.self)

        // After scouting a navigated element, graph should be back on root
        let graph = session.currentGraph
        XCTAssertEqual(graph.currentFingerprint, graph.rootFingerprint,
            "After scout backtrack, graph should point to parent screen")

        // Should have exactly 1 swipe (the backtrack) with fromX near left edge
        let backSwipes = input.swipes.filter { $0.fromX < 20 }
        XCTAssertEqual(backSwipes.count, 1,
            "Scout should swipe back exactly once after navigation")
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

    // MARK: - Screen Plan Integration

    func testExplorerBuildsPlanBeforeTapping() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Settings screen with chevron-backed items
        let rootElements: [TapPoint] = [
            TapPoint(text: "General", tapX: 100, tapY: 400, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 400, confidence: 0.95),
            TapPoint(text: "Privacy", tapX: 100, tapY: 480, confidence: 0.95),
            TapPoint(text: ">", tapX: 370, tapY: 480, confidence: 0.95),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Disable scouting to go straight to dive phase
        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 0,
            maxScoutsPerScreen: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let detailElements = makeElements(["About Phone", "iOS Version"])
        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        _ = explorer.step(describer: describer, input: input, strategy: MobileAppStrategy.self)

        // After step, a plan should have been built for the root screen
        let graph = session.currentGraph
        let rootFP = graph.rootFingerprint
        let plan = graph.screenPlan(for: rootFP)
        XCTAssertNotNil(plan, "Explorer should build a screen plan before tapping")
    }

    func testExplorerInvalidatesPlanAfterScroll() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 3,
            maxScoutsPerScreen: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // Mark the only element visited so scrolling triggers
        let graph = session.currentGraph
        let fp = graph.currentFingerprint
        graph.markElementVisited(fingerprint: fp, elementText: "Settings")

        // Manually set a plan to verify it gets cleared
        let fakePlan = [
            RankedElement(
                point: TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.9),
                score: 1.0, reason: "test"
            ),
        ]
        graph.setScreenPlan(for: fp, plan: fakePlan)
        XCTAssertNotNil(graph.screenPlan(for: fp), "Plan should exist before scroll")

        // Scroll reveals new elements
        let scrolledElements = makeElements(["General", "Privacy", "About"])
        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: scrolledElements, screenshotBase64: "img0_scrolled"),
        ])
        let input = MockInput()

        let result = explorer.step(describer: describer, input: input, strategy: MobileAppStrategy.self)

        if case .continue(let desc) = result {
            XCTAssertTrue(desc.contains("Scrolled"), "Should scroll. Got: \(desc)")
        } else {
            XCTFail("Expected .continue after scroll, got \(result)")
        }

        // Plan should be cleared after scroll revealed new elements
        XCTAssertNil(graph.screenPlan(for: fp),
            "Plan should be invalidated after scroll reveals new elements")
    }

    func testPlanPrioritizesChevronElements() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Mix of chevron-backed and fallback navigation elements
        let rootElements: [TapPoint] = [
            // Fallback (no chevron) at top
            TapPoint(text: "Identifiant Apple", tapX: 200, tapY: 240, confidence: 0.9),
            // Chevron-backed mid-screen
            TapPoint(text: "General", tapX: 100, tapY: 450, confidence: 0.9),
            TapPoint(text: ">", tapX: 370, tapY: 450, confidence: 0.9),
        ]
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        // Disable scouting
        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 0,
            maxScoutsPerScreen: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let detailElements = makeElements(["About Phone", "iOS Version"])
        let describer = MockDescriber(screens: [
            ScreenDescriber.DescribeResult(elements: rootElements, screenshotBase64: "img0"),
            ScreenDescriber.DescribeResult(elements: detailElements, screenshotBase64: "img1"),
        ])
        let input = MockInput()

        let result = explorer.step(describer: describer, input: input, strategy: MobileAppStrategy.self)

        if case .continue(let desc) = result {
            // The plan should prioritize "General" (chevron) over "Identifiant Apple" (fallback)
            XCTAssertTrue(desc.contains("General"),
                "Explorer should tap chevron-backed \"General\" first, not fallback. Got: \(desc)")
        } else {
            XCTFail("Expected .continue, got \(result)")
        }
    }
}
