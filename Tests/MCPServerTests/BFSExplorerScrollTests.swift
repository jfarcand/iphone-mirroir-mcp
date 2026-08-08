// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for action counter reset after scroll in BFS and DFS explorers.
// ABOUTME: Verifies that scrolling resets the per-screen action counter so new elements get tapped.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class BFSExplorerScrollTests: XCTestCase {

    private func makeElements(_ texts: [String], startY: Double = 120) -> [TapPoint] {
        makeExplorerElements(texts, startY: startY)
    }

    private func makeScreen(
        _ texts: [String], startY: Double = 120, img: String = "img"
    ) -> ScreenDescriber.DescribeResult {
        ScreenDescriber.DescribeResult(
            elements: makeElements(texts, startY: startY), screenshotBase64: img
        )
    }

    // MARK: - BFS: Action Counter Reset After Scroll

    /// After 5 taps exhaust maxActionsPerScreen, a scroll that finds new elements
    /// should reset the counter so the explorer taps the newly discovered elements.
    func testBFSResetsActionCounterAfterScroll() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        // Root has 6 elements but only 5 can be tapped before the action limit.
        // The 6th ("Mood") will only be reachable if scroll resets the counter.
        let rootElements = makeElements(
            ["Activity", "Heart", "Sleep", "Steps", "Nutrition"]
        )
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 2, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 1,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )
        let explorer = BFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        // The 6th element appears after scrolling
        let scrolledElements = makeElements(
            ["Activity", "Heart", "Sleep", "Steps", "Nutrition", "Mood"],
            startY: 120
        )
        let moodScreen = makeScreen(["Mood Details"], img: "imgMood")

        // Build the describe sequence.
        // The mock describer returns screens in order; once exhausted it recycles
        // the last entry. Provide generous padding so the explorer can complete
        // all phases (calibration, 5 taps, scroll, Mood tap, backtrack, finish).
        var screens: [ScreenDescriber.DescribeResult] = []
        let rootScreen = makeScreen(
            ["Activity", "Heart", "Sleep", "Steps", "Nutrition"], img: "img0"
        )
        let scrolledScreen = ScreenDescriber.DescribeResult(
            elements: scrolledElements, screenshotBase64: "img0_scrolled"
        )
        let rootWithMood = ScreenDescriber.DescribeResult(
            elements: scrolledElements, screenshotBase64: "img0_scrolled"
        )

        // Calibration scroll: same elements → 0 novel → breaks after 1 describe
        screens.append(rootScreen)

        // Steps 1-5: each does 2 OCR calls (viewport + after-tap → duplicate)
        for _ in 0..<5 {
            screens.append(rootScreen)
            screens.append(rootScreen)
        }

        // Step 6: viewport describe + scroll + after-scroll describe
        screens.append(rootScreen)
        screens.append(scrolledScreen)

        // Step 7: viewport describe (plan rebuilt) + tap Mood + after-tap
        screens.append(rootWithMood)
        screens.append(moodScreen)

        // Backtrack verify + subsequent steps: pad with rootWithMood
        for _ in 0..<6 {
            screens.append(rootWithMood)
        }

        let describer = MockExplorerDescriber(screens: screens)
        let input = MockExplorerInput()

        var results: [ExploreStepResult] = []
        for _ in 0..<12 {
            let result = explorer.step(
                describer: describer, input: input, strategy: MobileAppStrategy.self
            )
            results.append(result)
            if case .finished = result { break }
        }

        // Verify a scroll happened
        XCTAssertGreaterThanOrEqual(input.swipes.count, 1, "Should have scrolled at least once")

        // Verify "Mood" was tapped after scroll reset the counter.
        // Forward taps are at X=205; back taps are at X≈46.
        let forwardTaps = input.taps.filter { $0.x > 100 }
        XCTAssertGreaterThan(forwardTaps.count, 5,
            "Should tap more than 5 elements (scroll revealed new ones). Got \(forwardTaps.count)")

        // Verify the scroll result was reported
        let scrollResults = results.filter {
            if case .continue(let d) = $0 { return d.contains("Scrolled") }
            return false
        }
        XCTAssertEqual(scrollResults.count, 1, "Should have exactly one scroll step")
    }

    // MARK: - DFS: Action Counter Reset After Scroll

    /// Same test for DFS: after exhausting actions, scroll finds new elements,
    /// counter resets, and the explorer taps the new element instead of backtracking.
    func testDFSResetsActionCounterAfterScroll() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 1, scrollLimit: 1,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let rootScreen = ScreenDescriber.DescribeResult(
            elements: rootElements, screenshotBase64: "img0"
        )

        // Step 1: tap "Settings" → duplicate (no navigation)
        let describer1 = MockExplorerDescriber(screens: [
            rootScreen,  // dismissAlertIfPresent OCR
            rootScreen,  // performTap: after-tap OCR
        ])
        let input = MockExplorerInput()

        let step1 = explorer.step(
            describer: describer1, input: input, strategy: MobileAppStrategy.self
        )
        guard case .continue = step1 else {
            return XCTFail("Expected .continue for step 1, got \(step1)")
        }

        // Now actionsOnCurrentScreen=1 (at limit). Next step should scroll.
        // Scroll reveals a new element "About"
        let scrolledElements = makeElements(["Settings", "General", "About"])
        let scrolledScreen = ScreenDescriber.DescribeResult(
            elements: scrolledElements, screenshotBase64: "img0_scrolled"
        )

        let describer2 = MockExplorerDescriber(screens: [
            rootScreen,      // dismissAlertIfPresent OCR (sees Settings, General — both visited/at limit)
            scrolledScreen,  // performScrollIfAvailable: after-scroll OCR → finds "About"
        ])

        let step2 = explorer.step(
            describer: describer2, input: input, strategy: MobileAppStrategy.self
        )
        guard case .continue(let d2) = step2 else {
            return XCTFail("Expected .continue for step 2 (scroll), got \(step2)")
        }
        XCTAssertTrue(d2.contains("Scrolled"), "Should scroll. Got: \(d2)")

        // Step 3: counter is reset, should tap "About" (the new element)
        let aboutScreen = makeScreen(["About Version"], img: "imgAbout")
        let describer3 = MockExplorerDescriber(screens: [
            scrolledScreen,  // dismissAlertIfPresent OCR
            aboutScreen,     // performTap: after-tap OCR → new screen
        ])

        let step3 = explorer.step(
            describer: describer3, input: input, strategy: MobileAppStrategy.self
        )
        guard case .continue(let d3) = step3 else {
            return XCTFail("Expected .continue for step 3, got \(step3)")
        }
        XCTAssertTrue(d3.contains("new screen") || d3.contains("Tapped"),
            "Should tap a new element after scroll reset. Got: \(d3)")

        // Verify scroll happened
        XCTAssertEqual(input.swipes.count, 1, "Should have scrolled exactly once")
    }

    // MARK: - Scroll Budget Still Enforced

    /// Even with action counter reset, the scroll count still increments
    /// and respects scrollLimit. After 3 scrolls, no more scrolls happen.
    func testScrollBudgetStillEnforced() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["ItemA"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 6, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 1, scrollLimit: 2,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        let explorer = DFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let graph = session.currentGraph

        // Pre-visit the only element so the explorer immediately tries to scroll
        graph.markElementVisited(
            fingerprint: graph.currentFingerprint, elementText: "ItemA"
        )

        let rootScreen = ScreenDescriber.DescribeResult(
            elements: rootElements, screenshotBase64: "img0"
        )
        // Each scroll discovers one new element
        let scroll1Elements = makeElements(["ItemA", "ItemB"])
        let scroll1Screen = ScreenDescriber.DescribeResult(
            elements: scroll1Elements, screenshotBase64: "img_s1"
        )
        let scroll2Elements = makeElements(["ItemA", "ItemB", "ItemC"])
        let scroll2Screen = ScreenDescriber.DescribeResult(
            elements: scroll2Elements, screenshotBase64: "img_s2"
        )

        let input = MockExplorerInput()

        // Step 1: all visited → scroll #1 → finds ItemB
        let describer1 = MockExplorerDescriber(screens: [
            rootScreen,    // dismissAlertIfPresent OCR
            scroll1Screen, // after-scroll OCR → novel
        ])
        let step1 = explorer.step(
            describer: describer1, input: input, strategy: MobileAppStrategy.self
        )
        guard case .continue(let d1) = step1 else {
            return XCTFail("Expected .continue for scroll 1, got \(step1)")
        }
        XCTAssertTrue(d1.contains("Scrolled"), "Should scroll #1. Got: \(d1)")

        // Step 2: tap ItemB → duplicate
        let describer2 = MockExplorerDescriber(screens: [
            scroll1Screen, // dismissAlertIfPresent
            scroll1Screen, // after-tap → duplicate
        ])
        let step2 = explorer.step(
            describer: describer2, input: input, strategy: MobileAppStrategy.self
        )
        guard case .continue = step2 else {
            return XCTFail("Expected .continue for tap, got \(step2)")
        }

        // Step 3: all visited again → scroll #2 → finds ItemC
        graph.markElementVisited(
            fingerprint: graph.currentFingerprint, elementText: "ItemB"
        )
        let describer3 = MockExplorerDescriber(screens: [
            scroll1Screen, // dismissAlertIfPresent
            scroll2Screen, // after-scroll OCR → novel
        ])
        let step3 = explorer.step(
            describer: describer3, input: input, strategy: MobileAppStrategy.self
        )
        guard case .continue(let d3) = step3 else {
            return XCTFail("Expected .continue for scroll 2, got \(step3)")
        }
        XCTAssertTrue(d3.contains("Scrolled"), "Should scroll #2. Got: \(d3)")

        // Step 4: tap ItemC → duplicate
        let describer4 = MockExplorerDescriber(screens: [
            scroll2Screen,
            scroll2Screen,
        ])
        let step4 = explorer.step(
            describer: describer4, input: input, strategy: MobileAppStrategy.self
        )
        guard case .continue = step4 else {
            return XCTFail("Expected .continue for tap, got \(step4)")
        }

        // Step 5: all visited, scroll budget (2) exhausted → should finish (root, no backtrack)
        graph.markElementVisited(
            fingerprint: graph.currentFingerprint, elementText: "ItemC"
        )
        let describer5 = MockExplorerDescriber(screens: [
            scroll2Screen,
        ])
        let step5 = explorer.step(
            describer: describer5, input: input, strategy: MobileAppStrategy.self
        )
        if case .finished = step5 {
            // Expected: scroll budget exhausted, at root, nothing left
        } else {
            XCTFail("Expected .finished after scroll budget exhausted, got \(step5)")
        }

        // Verify exactly 2 scrolls happened (not more)
        XCTAssertEqual(input.swipes.count, 2,
            "Should have scrolled exactly twice (scrollLimit=2)")
    }

    // MARK: - BFS: Multi-Viewport Exploration

    // MARK: - BFS: Per-Viewport Scrolling Bypasses Scroll Exhaustion

    /// When skipCalibration is true, performScrollIfAvailable should scroll even
    /// after CalibrationScroller marked the page as scroll-exhausted. This is the
    /// core fix that enables per-viewport exploration.
    func testSkipCalibrationBypassesScrollExhaustion() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 2, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 1, scrollLimit: 2,
            calibrationScrollLimit: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        // WITH skipCalibration: scroll should work despite exhaustion
        let explorer = BFSExplorer(
            session: session, budget: budget, skipCalibration: true
        )
        explorer.markStarted()

        // Manually mark scroll as exhausted (simulates CalibrationScroller)
        let graph = session.currentGraph
        graph.markScrollExhausted(fingerprint: graph.rootFingerprint)

        let rootScreen = makeScreen(["Settings", "General"])
        let scrolledScreen = makeScreen(["Settings", "General", "About"])

        // Step 1: tap Settings → duplicate. Step 2: action limit → scroll → "About" is novel
        let screens: [ScreenDescriber.DescribeResult] = [
            rootScreen, rootScreen,     // step 1: viewport + after-tap
            rootScreen, scrolledScreen,  // step 2: viewport + scroll result
        ]
        let describer = MockExplorerDescriber(screens: screens)
        let input = MockExplorerInput()

        var scrollHappened = false
        for _ in 0..<4 {
            let result = explorer.step(
                describer: describer, input: input, strategy: MobileAppStrategy.self
            )
            if case .continue(let d) = result, d.contains("Scrolled") {
                scrollHappened = true
                break
            }
        }

        XCTAssertTrue(scrollHappened,
            "skipCalibration=true should allow scrolling even when scroll exhausted")
        XCTAssertGreaterThanOrEqual(input.swipes.filter({ $0.fromY > $0.toY }).count, 1,
            "Should have performed at least one scroll-down swipe")
    }

    // MARK: - Calibration Scroll Cap From Recipe

    /// A matched recipe declaring calibrationScrollLimit=2 must cap calibration
    /// scrolling at 2 forward swipes even when every scroll reveals novel
    /// elements (infinite feed) and the budget default (15) would allow more.
    func testCalibrationScrollCappedByRecipeLimit() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")
        session.capture(
            elements: makeElements(["Post1"]), hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let recipe = ScreenRecipe(
            name: "feed", platform: "ios", description: "Feed",
            requiredComponents: ["feed-post"],
            supportingComponents: [], forbiddenComponents: [],
            navigationModel: RecipeNavigationModel(
                type: "infinite-scroll", backtrack: "tap-tab",
                scrollBehavior: "infinite", depthPattern: "flat",
                calibrationScrollLimit: 2),
            explorationHints: [])
        session.setRecipeMatch(RecipeMatch(recipe: recipe, score: 10, reason: "test"))

        let budget = ExplorationBudget(
            maxDepth: 2, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 1,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )
        // No bridge → scrollAndCollect uses the simple scroll loop.
        let explorer = BFSExplorer(session: session, budget: budget)
        XCTAssertEqual(explorer.effectiveCalibrationScrollLimit, 2,
            "Recipe cap should override the budget default (15)")

        // Every scroll reveals a new post — only the cap can stop the loop.
        var texts = ["Post1"]
        let screens: [ScreenDescriber.DescribeResult] = (2...20).map { i in
            texts.append("Post\(i)")
            return makeScreen(texts)
        }
        let describer = MockExplorerDescriber(screens: screens)
        let input = MockExplorerInput()

        let graph = session.currentGraph
        let data = explorer.scrollAndCollect(
            fingerprint: graph.rootFingerprint, describer: describer, input: input
        )

        XCTAssertEqual(data.scrollCount, 2, "Recipe cap should stop calibration at 2 scrolls")
        // Forward calibration swipes go top-to-bottom on screen (fromY > toY);
        // scroll-back swipes are the reverse.
        let forwardSwipes = input.swipes.filter { $0.fromY > $0.toY }
        XCTAssertEqual(forwardSwipes.count, 2,
            "Should perform exactly 2 forward calibration swipes")
    }

    /// Same recipe cap, but through the bridge path: with a bridge present,
    /// scrollAndCollect delegates to describeFullPage/CalibrationScroller and
    /// must pass the effective (recipe-capped) limit as maxScrolls.
    func testCalibrationScrollCapReachesCalibrationScroller() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")
        session.capture(
            elements: makeElements(["Post1"]), hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let recipe = ScreenRecipe(
            name: "feed", platform: "ios", description: "Feed",
            requiredComponents: ["feed-post"],
            supportingComponents: [], forbiddenComponents: [],
            navigationModel: RecipeNavigationModel(
                type: "infinite-scroll", backtrack: "tap-tab",
                scrollBehavior: "infinite", depthPattern: "flat",
                calibrationScrollLimit: 2),
            explorationHints: [])
        session.setRecipeMatch(RecipeMatch(recipe: recipe, score: 10, reason: "test"))

        let budget = ExplorationBudget(
            maxDepth: 2, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 5, scrollLimit: 1,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )
        let explorer = BFSExplorer(
            session: session, budget: budget, bridge: StubWindowBridge()
        )

        // Every scroll reveals a new post — only the cap can stop the scroller.
        var texts = ["Post1"]
        var screens: [ScreenDescriber.DescribeResult] = [makeScreen(texts)]
        for i in 2...20 {
            texts.append("Post\(i)")
            screens.append(makeScreen(texts))
        }
        let describer = MockExplorerDescriber(screens: screens)
        let input = MockExplorerInput()

        let graph = session.currentGraph
        let data = explorer.scrollAndCollect(
            fingerprint: graph.rootFingerprint, describer: describer, input: input
        )

        XCTAssertTrue(data.usedCalibrationScroller,
            "A bridge must route calibration through CalibrationScroller")
        XCTAssertEqual(data.scrollCount, 2,
            "CalibrationScroller must receive the recipe-capped maxScrolls")
        let forwardSwipes = input.swipes.filter { $0.fromY > $0.toY }
        XCTAssertEqual(forwardSwipes.count, 2,
            "Should perform exactly 2 forward calibration swipes via the bridge path")
    }

    /// Without skipCalibration, scroll-exhausted screens should NOT scroll further.
    func testScrollExhaustedBlocksWithoutSkipCalibration() {
        let session = ExplorationSession()
        session.start(appName: "TestApp", goal: "test")

        let rootElements = makeElements(["Settings", "General"])
        session.capture(
            elements: rootElements, hints: [], icons: [],
            actionType: nil, arrivedVia: nil, screenshotBase64: "img0"
        )

        let budget = ExplorationBudget(
            maxDepth: 2, maxScreens: 30, maxTimeSeconds: 300,
            maxActionsPerScreen: 1, scrollLimit: 2,
            calibrationScrollLimit: 0,
            skipPatterns: ExplorationBudget.default.skipPatterns
        )

        // WITHOUT skipCalibration: scroll should be blocked by exhaustion
        let explorer = BFSExplorer(session: session, budget: budget)
        explorer.markStarted()

        let graph = session.currentGraph
        graph.markScrollExhausted(fingerprint: graph.rootFingerprint)

        let rootScreen = makeScreen(["Settings", "General"])
        let screens = [ScreenDescriber.DescribeResult](repeating: rootScreen, count: 10)
        let describer = MockExplorerDescriber(screens: screens)
        let input = MockExplorerInput()

        for _ in 0..<4 {
            let result = explorer.step(
                describer: describer, input: input, strategy: MobileAppStrategy.self
            )
            if case .finished = result { break }
        }

        // Should NOT have scrolled — exhaustion blocks it
        let downSwipes = input.swipes.filter { $0.fromY > $0.toY }
        XCTAssertEqual(downSwipes.count, 0,
            "Scroll-exhausted screen should not scroll when skipCalibration is false")
    }
}
