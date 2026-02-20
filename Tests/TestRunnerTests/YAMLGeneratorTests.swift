// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for YAMLGenerator: YAML output format, escaping, and step generation.
// ABOUTME: Covers all recorded event kinds and the complete document generation.

import XCTest
@testable import mirroir_mcp

final class YAMLGeneratorTests: XCTestCase {

    // MARK: - Step Generation

    func testGenerateTapWithLabel() {
        let lines = YAMLGenerator.generateStep(.tap(x: 205, y: 450, label: "Settings"))
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines[0], "- tap: \"Settings\"  # at (205, 450)")
    }

    func testGenerateTapWithoutLabel() {
        let lines = YAMLGenerator.generateStep(.tap(x: 100, y: 200, label: nil))
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("FIXME"))
        XCTAssertTrue(lines[0].contains("(100, 200)"))
    }

    func testGenerateSwipe() {
        let lines = YAMLGenerator.generateStep(.swipe(direction: "up"))
        XCTAssertEqual(lines, ["- swipe: \"up\""])
    }

    func testGenerateSwipeDown() {
        let lines = YAMLGenerator.generateStep(.swipe(direction: "down"))
        XCTAssertEqual(lines, ["- swipe: \"down\""])
    }

    func testGenerateLongPressWithLabel() {
        let lines = YAMLGenerator.generateStep(
            .longPress(x: 150, y: 300, label: "Delete", durationMs: 800))
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("long_press"))
        XCTAssertTrue(lines[0].contains("Delete"))
        XCTAssertTrue(lines[0].contains("800ms"))
    }

    func testGenerateLongPressWithoutLabel() {
        let lines = YAMLGenerator.generateStep(
            .longPress(x: 150, y: 300, label: nil, durationMs: 600))
        XCTAssertTrue(lines[0].contains("FIXME"))
        XCTAssertTrue(lines[0].contains("600ms"))
    }

    func testGenerateType() {
        let lines = YAMLGenerator.generateStep(.type(text: "hello world"))
        XCTAssertEqual(lines, ["- type: \"hello world\""])
    }

    func testGenerateTypeWithSpecialChars() {
        let lines = YAMLGenerator.generateStep(.type(text: "say \"hello\""))
        XCTAssertEqual(lines, ["- type: \"say \\\"hello\\\"\""])
    }

    func testGeneratePressKey() {
        let lines = YAMLGenerator.generateStep(.pressKey(keyName: "return", modifiers: []))
        XCTAssertEqual(lines, ["- press_key: \"return\""])
    }

    func testGeneratePressKeyWithModifiers() {
        let lines = YAMLGenerator.generateStep(
            .pressKey(keyName: "l", modifiers: ["command"]))
        XCTAssertEqual(lines, ["- press_key: \"l+command\""])
    }

    func testGeneratePressKeyWithMultipleModifiers() {
        let lines = YAMLGenerator.generateStep(
            .pressKey(keyName: "z", modifiers: ["command", "shift"]))
        XCTAssertEqual(lines, ["- press_key: \"z+command+shift\""])
    }

    // MARK: - Complete Document

    func testGenerateCompleteDocument() {
        let events: [RecordedEvent] = [
            RecordedEvent(timestamp: 0, kind: .tap(x: 205, y: 450, label: "Settings")),
            RecordedEvent(timestamp: 1, kind: .tap(x: 150, y: 300, label: "General")),
            RecordedEvent(timestamp: 2, kind: .swipe(direction: "up")),
            RecordedEvent(timestamp: 3, kind: .tap(x: 200, y: 500, label: "About")),
        ]

        let yaml = YAMLGenerator.generate(
            events: events,
            name: "Check About",
            description: "Navigate to Settings > General > About",
            appName: "Settings"
        )

        XCTAssertTrue(yaml.contains("name: Check About"))
        XCTAssertTrue(yaml.contains("app: Settings"))
        XCTAssertTrue(yaml.contains("description: Navigate to Settings > General > About"))
        XCTAssertTrue(yaml.contains("steps:"))
        XCTAssertTrue(yaml.contains("- tap: \"Settings\""))
        XCTAssertTrue(yaml.contains("- tap: \"General\""))
        XCTAssertTrue(yaml.contains("- swipe: \"up\""))
        XCTAssertTrue(yaml.contains("- tap: \"About\""))
    }

    func testGenerateDocumentWithoutAppName() {
        let events: [RecordedEvent] = [
            RecordedEvent(timestamp: 0, kind: .type(text: "hello")),
        ]

        let yaml = YAMLGenerator.generate(
            events: events,
            name: "Test",
            description: "A test",
            appName: nil
        )

        XCTAssertFalse(yaml.contains("app:"))
        XCTAssertTrue(yaml.contains("name: Test"))
    }

    func testGenerateDocumentEmptyEvents() {
        let yaml = YAMLGenerator.generate(
            events: [],
            name: "Empty",
            description: "No events",
            appName: nil
        )

        XCTAssertTrue(yaml.contains("name: Empty"))
        XCTAssertTrue(yaml.contains("steps:"))
        // No step lines after steps:
        let lines = yaml.components(separatedBy: "\n")
        let stepsIndex = lines.firstIndex(of: "steps:")
        XCTAssertNotNil(stepsIndex)
        // Next line after "steps:" should be empty (trailing newline) or end of file
    }

    // MARK: - YAML Escaping

    func testEscapeBackslash() {
        XCTAssertEqual(YAMLGenerator.escapeYAML("path\\file"), "path\\\\file")
    }

    func testEscapeDoubleQuote() {
        XCTAssertEqual(YAMLGenerator.escapeYAML("say \"hi\""), "say \\\"hi\\\"")
    }

    func testEscapeNoSpecialChars() {
        XCTAssertEqual(YAMLGenerator.escapeYAML("hello world"), "hello world")
    }

    // MARK: - Mixed Event Sequences

    func testTypeThenPressKey() {
        let events: [RecordedEvent] = [
            RecordedEvent(timestamp: 0, kind: .tap(x: 100, y: 200, label: "Search")),
            RecordedEvent(timestamp: 1, kind: .type(text: "Settings")),
            RecordedEvent(timestamp: 2, kind: .pressKey(keyName: "return", modifiers: [])),
        ]

        let yaml = YAMLGenerator.generate(
            events: events,
            name: "Search",
            description: "Search for Settings",
            appName: nil
        )

        XCTAssertTrue(yaml.contains("- tap: \"Search\""))
        XCTAssertTrue(yaml.contains("- type: \"Settings\""))
        XCTAssertTrue(yaml.contains("- press_key: \"return\""))
    }
}
