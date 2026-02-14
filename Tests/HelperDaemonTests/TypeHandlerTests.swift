// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for the type command handler: empty text, keyboard readiness, character mapping.
// ABOUTME: Verifies typed keystrokes, skipped characters, and warning messages.

import XCTest
import Foundation
import HelperLib
@testable import iphone_mirroir_helper

final class TypeHandlerTests: XCTestCase {

    private var server: CommandServer!
    private var karabiner: StubKarabiner!

    override func setUp() {
        super.setUp()
        karabiner = StubKarabiner()
        server = CommandServer(karabiner: karabiner)
    }

    private func processJSON(_ dict: [String: Any]) -> [String: Any]? {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let response = server.processCommand(data: data)
        return try? JSONSerialization.jsonObject(with: response) as? [String: Any]
    }

    // MARK: - Validation

    func testEmptyText() {
        let result = processJSON(["action": "type", "text": ""])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("non-empty"))
    }

    func testKeyboardNotReady() {
        karabiner.isKeyboardReady = false
        let result = processJSON(["action": "type", "text": "hello"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("keyboard device not ready"))
    }

    // MARK: - Success

    func testAllCharsHaveHIDMapping() {
        let result = processJSON(["action": "type", "text": "abc"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        // Each character should produce a typeKey call
        XCTAssertEqual(karabiner.typedKeys.count, 3)
    }

    func testSomeCharsMissingMapping() {
        // Use a character that has no US QWERTY HID mapping (e.g., emoji)
        let result = processJSON(["action": "type", "text": "a\u{1F600}b"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        // 'a' and 'b' should be typed, emoji skipped
        XCTAssertEqual(karabiner.typedKeys.count, 2)
        let skipped = result?["skipped_characters"] as? String ?? ""
        XCTAssertTrue(skipped.contains("\u{1F600}"))
    }

    func testTextWithOnlyMissingChars() {
        let result = processJSON(["action": "type", "text": "\u{1F600}\u{1F601}"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertEqual(karabiner.typedKeys.count, 0)
        let skipped = result?["skipped_characters"] as? String ?? ""
        XCTAssertFalse(skipped.isEmpty)
        let warning = result?["warning"] as? String ?? ""
        XCTAssertTrue(warning.contains("no US QWERTY HID mapping"))
    }
}
