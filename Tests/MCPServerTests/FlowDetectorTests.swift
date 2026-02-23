// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Unit tests for FlowDetector: cycle detection, flow boundaries, and stuck detection.
// ABOUTME: Verifies pure transformation functions using synthetic TapPoint and action log data.

import XCTest
@testable import HelperLib
@testable import mirroir_mcp

final class FlowDetectorTests: XCTestCase {

    // MARK: - isBackAtStart

    func testIsBackAtStartWithSameScreen() {
        let elements = [
            TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98),
            TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95),
        ]
        XCTAssertTrue(
            FlowDetector.isBackAtStart(
                currentElements: elements, startElements: elements, screenCount: 3),
            "Same elements should be detected as back at start")
    }

    func testIsBackAtStartWithDifferentScreen() {
        let start = [
            TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98),
            TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95),
        ]
        let current = [
            TapPoint(text: "About", tapX: 205, tapY: 120, confidence: 0.96),
            TapPoint(text: "iOS Version", tapX: 205, tapY: 300, confidence: 0.88),
        ]
        XCTAssertFalse(
            FlowDetector.isBackAtStart(
                currentElements: current, startElements: start, screenCount: 3),
            "Different elements should not be detected as back at start")
    }

    func testIsBackAtStartRequiresMinScreens() {
        let elements = [
            TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98),
        ]
        XCTAssertFalse(
            FlowDetector.isBackAtStart(
                currentElements: elements, startElements: elements, screenCount: 1),
            "Should not detect flow boundary with only 1 screen captured")
    }

    // MARK: - consecutiveDuplicates

    func testConsecutiveDuplicatesAtEnd() {
        let log: [ExplorationAction] = [
            ExplorationAction(actionType: "tap", arrivedVia: "General", wasDuplicate: false),
            ExplorationAction(actionType: "tap", arrivedVia: "About", wasDuplicate: true),
            ExplorationAction(actionType: "tap", arrivedVia: "Privacy", wasDuplicate: true),
            ExplorationAction(actionType: "tap", arrivedVia: "Display", wasDuplicate: true),
        ]
        XCTAssertEqual(FlowDetector.consecutiveDuplicates(in: log), 3)
    }

    func testConsecutiveDuplicatesNoneAtEnd() {
        let log: [ExplorationAction] = [
            ExplorationAction(actionType: "tap", arrivedVia: "General", wasDuplicate: true),
            ExplorationAction(actionType: "tap", arrivedVia: "About", wasDuplicate: false),
        ]
        XCTAssertEqual(FlowDetector.consecutiveDuplicates(in: log), 0)
    }

    func testConsecutiveDuplicatesEmptyLog() {
        XCTAssertEqual(FlowDetector.consecutiveDuplicates(in: []), 0)
    }

    // MARK: - isStuck

    func testIsStuckWhenThresholdReached() {
        let log: [ExplorationAction] = (0..<3).map { _ in
            ExplorationAction(actionType: "tap", arrivedVia: "Button", wasDuplicate: true)
        }
        XCTAssertTrue(FlowDetector.isStuck(actionLog: log),
            "Should detect stuck state after \(FlowDetector.stuckThreshold) consecutive duplicates")
    }

    func testIsNotStuckBelowThreshold() {
        let log: [ExplorationAction] = [
            ExplorationAction(actionType: "tap", arrivedVia: "A", wasDuplicate: true),
            ExplorationAction(actionType: "tap", arrivedVia: "B", wasDuplicate: true),
        ]
        XCTAssertFalse(FlowDetector.isStuck(actionLog: log),
            "Should not detect stuck state below threshold")
    }

    // MARK: - visitCount

    func testVisitCountFindsMatchingScreens() {
        let elements = [
            TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98),
            TapPoint(text: "General", tapX: 205, tapY: 340, confidence: 0.95),
        ]
        let screens = [
            ExploredScreen(index: 0, elements: elements, hints: [],
                actionType: nil, arrivedVia: nil, screenshotBase64: "img0"),
            ExploredScreen(index: 1,
                elements: [TapPoint(text: "About", tapX: 205, tapY: 120, confidence: 0.96)],
                hints: [], actionType: "tap", arrivedVia: "About", screenshotBase64: "img1"),
            ExploredScreen(index: 2, elements: elements, hints: [],
                actionType: "press_key", arrivedVia: "[", screenshotBase64: "img2"),
        ]
        XCTAssertEqual(
            FlowDetector.visitCount(currentElements: elements, capturedScreens: screens), 2,
            "Should count 2 screens matching the given elements")
    }

    func testVisitCountZeroWhenNoMatch() {
        let elements = [
            TapPoint(text: "Never Seen", tapX: 100, tapY: 100, confidence: 0.9),
        ]
        let screens = [
            ExploredScreen(index: 0,
                elements: [TapPoint(text: "Settings", tapX: 205, tapY: 120, confidence: 0.98)],
                hints: [], actionType: nil, arrivedVia: nil, screenshotBase64: "img0"),
        ]
        XCTAssertEqual(
            FlowDetector.visitCount(currentElements: elements, capturedScreens: screens), 0)
    }
}
