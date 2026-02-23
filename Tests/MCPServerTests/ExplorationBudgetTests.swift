// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for ExplorationBudget: limit enforcement and element skip patterns.
// ABOUTME: Verifies depth, screen count, time limits, and dangerous action filtering.

import XCTest
@testable import mirroir_mcp

final class ExplorationBudgetTests: XCTestCase {

    // MARK: - Default Budget

    func testDefaultBudgetValues() {
        let budget = ExplorationBudget.default

        XCTAssertEqual(budget.maxDepth, 6)
        XCTAssertEqual(budget.maxScreens, 30)
        XCTAssertEqual(budget.maxTimeSeconds, 300)
        XCTAssertEqual(budget.maxActionsPerScreen, 5)
        XCTAssertEqual(budget.scrollLimit, 3)
        XCTAssertFalse(budget.skipPatterns.isEmpty)
    }

    // MARK: - isExhausted

    func testNotExhaustedWithinLimits() {
        let budget = ExplorationBudget.default

        XCTAssertFalse(budget.isExhausted(depth: 3, screenCount: 10, elapsedSeconds: 60))
    }

    func testExhaustedByDepth() {
        let budget = ExplorationBudget.default

        XCTAssertTrue(budget.isExhausted(depth: 6, screenCount: 5, elapsedSeconds: 30))
    }

    func testExhaustedByScreenCount() {
        let budget = ExplorationBudget.default

        XCTAssertTrue(budget.isExhausted(depth: 2, screenCount: 30, elapsedSeconds: 30))
    }

    func testExhaustedByTime() {
        let budget = ExplorationBudget.default

        XCTAssertTrue(budget.isExhausted(depth: 2, screenCount: 5, elapsedSeconds: 300))
    }

    func testCustomBudgetLimits() {
        let budget = ExplorationBudget(
            maxDepth: 3,
            maxScreens: 10,
            maxTimeSeconds: 60,
            maxActionsPerScreen: 3,
            scrollLimit: 2,
            skipPatterns: ["Delete"]
        )

        XCTAssertFalse(budget.isExhausted(depth: 2, screenCount: 9, elapsedSeconds: 59))
        XCTAssertTrue(budget.isExhausted(depth: 3, screenCount: 5, elapsedSeconds: 30))
        XCTAssertTrue(budget.isExhausted(depth: 1, screenCount: 10, elapsedSeconds: 30))
        XCTAssertTrue(budget.isExhausted(depth: 1, screenCount: 5, elapsedSeconds: 60))
    }

    // MARK: - shouldSkipElement

    func testSkipDestructiveActions() {
        let budget = ExplorationBudget.default

        XCTAssertTrue(budget.shouldSkipElement(text: "Delete Account"))
        XCTAssertTrue(budget.shouldSkipElement(text: "Sign Out"))
        XCTAssertTrue(budget.shouldSkipElement(text: "Log Out"))
        XCTAssertTrue(budget.shouldSkipElement(text: "Reset All Settings"))
        XCTAssertTrue(budget.shouldSkipElement(text: "Erase All Content"))
        XCTAssertTrue(budget.shouldSkipElement(text: "Remove All"))
    }

    func testSkipIsCaseInsensitive() {
        let budget = ExplorationBudget.default

        XCTAssertTrue(budget.shouldSkipElement(text: "delete account"))
        XCTAssertTrue(budget.shouldSkipElement(text: "SIGN OUT"))
    }

    func testDoNotSkipSafeElements() {
        let budget = ExplorationBudget.default

        XCTAssertFalse(budget.shouldSkipElement(text: "General"))
        XCTAssertFalse(budget.shouldSkipElement(text: "About"))
        XCTAssertFalse(budget.shouldSkipElement(text: "Privacy"))
        XCTAssertFalse(budget.shouldSkipElement(text: "Display & Brightness"))
    }
}
