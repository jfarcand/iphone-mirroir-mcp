// ABOUTME: Tests for press_key command: special key lookup, single character mapping, unknown keys.
// ABOUTME: Verifies HIDSpecialKeyMap and HIDKeyMap integration in the handlePressKey handler.

import XCTest
import Foundation
import HelperLib
@testable import iphone_mirroir_helper

final class PressKeyLookupTests: XCTestCase {

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

    // MARK: - Special Keys

    func testReturnKey() {
        let result = processJSON(["action": "press_key", "key": "return"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertEqual(karabiner.typedKeys.count, 1)
    }

    func testEscapeKey() {
        let result = processJSON(["action": "press_key", "key": "escape"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertEqual(karabiner.typedKeys.count, 1)
    }

    // MARK: - Single Characters

    func testSingleCharacterA() {
        let result = processJSON(["action": "press_key", "key": "a"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertEqual(karabiner.typedKeys.count, 1)
        // 'a' keycode is 0x04 in USB HID
        XCTAssertEqual(karabiner.typedKeys.first?.keycode, 0x04)
    }

    func testUppercaseA() {
        let result = processJSON(["action": "press_key", "key": "A"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertEqual(karabiner.typedKeys.count, 1)
        // Uppercase A should include shift modifier
        let modifiers = karabiner.typedKeys.first?.modifiers ?? []
        XCTAssertTrue(modifiers.contains(.leftShift))
    }

    // MARK: - Unknown Keys

    func testUnknownKey() {
        let result = processJSON(["action": "press_key", "key": "nonexistent"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("Unknown key"))
        XCTAssertTrue(error.contains("Supported"))
    }

    func testEmptyKey() {
        let result = processJSON(["action": "press_key", "key": ""])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("Unknown key"))
    }

    // MARK: - Keyboard Not Ready

    func testKeyboardNotReady() {
        karabiner.isKeyboardReady = false
        let result = processJSON(["action": "press_key", "key": "return"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("keyboard device not ready"))
    }

    // MARK: - Modifiers

    func testKeyWithModifiers() {
        let result = processJSON([
            "action": "press_key",
            "key": "l",
            "modifiers": ["command"],
        ])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertEqual(karabiner.typedKeys.count, 1)
        let modifiers = karabiner.typedKeys.first?.modifiers ?? []
        XCTAssertTrue(modifiers.contains(.leftCommand))
    }
}
