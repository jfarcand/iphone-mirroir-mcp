// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for SocialAppStrategy: social-specific skip patterns, depth caps, and delegation.
// ABOUTME: Verifies that MobileAppStrategy delegation works and social enhancements layer correctly.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class SocialAppStrategyTests: XCTestCase {

    // MARK: - Test Helpers

    private func makeElements(_ texts: [String], startY: Double = 120) -> [TapPoint] {
        texts.enumerated().map { (i, text) in
            TapPoint(text: text, tapX: 205, tapY: startY + Double(i) * 80, confidence: 0.95)
        }
    }

    // MARK: - Classification Delegation

    func testClassifyScreenDelegatesToMobile() {
        // Tab bar screen should be classified same as MobileAppStrategy
        let elements = makeElements(["Home", "Search", "Profile", "Settings", "More"], startY: 800)
        let result = SocialAppStrategy.classifyScreen(elements: elements, hints: [])
        let mobileResult = MobileAppStrategy.classifyScreen(elements: elements, hints: [])
        XCTAssertEqual(result, mobileResult,
            "SocialAppStrategy should delegate classifyScreen to MobileAppStrategy")
    }

    // MARK: - Skip Patterns

    func testSkipsSocialEngagementElements() {
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Sponsored Post"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Promoted"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Follow"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Unfollow"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Share"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Repost"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Upvote"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Downvote"))
    }

    func testSkipsSocialPatternsCaseInsensitive() {
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "SPONSORED"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "stories"))
    }

    func testSkipInheritsBasePatterns() {
        // Base budget patterns should still be skipped
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Delete Account"))
        XCTAssertTrue(SocialAppStrategy.shouldSkip(elementText: "Sign Out"))
    }

    func testDoesNotSkipSafeNavElements() {
        XCTAssertFalse(SocialAppStrategy.shouldSkip(elementText: "Home"))
        XCTAssertFalse(SocialAppStrategy.shouldSkip(elementText: "Search"))
        XCTAssertFalse(SocialAppStrategy.shouldSkip(elementText: "Profile"))
        XCTAssertFalse(SocialAppStrategy.shouldSkip(elementText: "Settings"))
    }

    // MARK: - Ranking Filters

    func testRankingFiltersSocialSkipPatterns() {
        let elements = makeElements(["Home", "Sponsored Post", "Settings", "Upvote", "About"])
        let ranked = SocialAppStrategy.rankElements(
            elements: elements, icons: [],
            visitedElements: [], depth: 0, screenType: .list
        )

        let rankedTexts = ranked.map(\.text)
        XCTAssertFalse(rankedTexts.contains("Sponsored Post"),
            "Sponsored content should be filtered from ranking")
        XCTAssertFalse(rankedTexts.contains("Upvote"),
            "Upvote should be filtered from ranking")
        XCTAssertTrue(rankedTexts.contains("Home"))
        XCTAssertTrue(rankedTexts.contains("Settings"))
        XCTAssertTrue(rankedTexts.contains("About"))
    }

    // MARK: - Terminal at Profile Depth

    func testTerminalAtProfileDepthCap() {
        let elements = makeElements(["User Profile", "Posts", "Comments"])
        let result = SocialAppStrategy.isTerminal(
            elements: elements, depth: 3,
            budget: .default, screenType: .detail
        )
        XCTAssertTrue(result,
            "Detail screen at depth >= 3 should be terminal in social strategy")
    }

    func testNotTerminalBelowProfileDepthCap() {
        let elements = makeElements(["User Profile", "Posts", "Comments"])
        let result = SocialAppStrategy.isTerminal(
            elements: elements, depth: 2,
            budget: .default, screenType: .detail
        )
        XCTAssertFalse(result,
            "Detail screen at depth < 3 should not be terminal")
    }

    func testTerminalStillRespectsBaseBudgetDepth() {
        let elements = makeElements(["Settings", "About", "Version"])
        let result = SocialAppStrategy.isTerminal(
            elements: elements, depth: 6,
            budget: .default, screenType: .list
        )
        XCTAssertTrue(result,
            "Should respect base budget max depth regardless of screen type")
    }

    // MARK: - Backtrack Delegation

    func testBacktrackDelegatesToMobile() {
        let hints = ["Back navigation detected"]
        let social = SocialAppStrategy.backtrackMethod(currentHints: hints, depth: 2)
        let mobile = MobileAppStrategy.backtrackMethod(currentHints: hints, depth: 2)
        XCTAssertEqual(social, mobile,
            "Backtrack should delegate to MobileAppStrategy")
    }

    // MARK: - Fingerprint Delegation

    func testFingerprintDelegatesToMobile() {
        let elements = makeElements(["Test", "Screen"])
        let social = SocialAppStrategy.extractFingerprint(elements: elements, icons: [])
        let mobile = MobileAppStrategy.extractFingerprint(elements: elements, icons: [])
        XCTAssertEqual(social, mobile,
            "Fingerprint should delegate to MobileAppStrategy")
    }
}
