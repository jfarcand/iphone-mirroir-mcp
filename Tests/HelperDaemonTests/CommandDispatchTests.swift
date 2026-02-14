// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for CommandServer.processCommand dispatch: JSON parsing, action routing, error paths.
// ABOUTME: Verifies that invalid input returns correct error responses and valid actions dispatch properly.

import XCTest
import Foundation
import HelperLib
@testable import iphone_mirroir_helper

final class CommandDispatchTests: XCTestCase {

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

    // MARK: - Invalid Input

    func testInvalidJSON() {
        let data = Data("not json{".utf8)
        let response = server.processCommand(data: data)
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            return XCTFail("Expected JSON response")
        }
        XCTAssertEqual(json["ok"] as? Bool, false)
        let error = json["error"] as? String ?? ""
        XCTAssertTrue(error.contains("Invalid JSON"))
    }

    func testMissingActionKey() {
        let result = processJSON(["x": 100])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("missing 'action' key"))
    }

    func testUnknownAction() {
        let result = processJSON(["action": "fly"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("Unknown action: fly"))
    }

    func testEmptyData() {
        let response = server.processCommand(data: Data())
        guard let json = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
            return XCTFail("Expected JSON response")
        }
        XCTAssertEqual(json["ok"] as? Bool, false)
    }

    // MARK: - Valid Dispatch

    func testStatusAction() {
        karabiner.isConnected = true
        karabiner.isKeyboardReady = true
        karabiner.isPointingReady = false
        let result = processJSON(["action": "status"])
        XCTAssertEqual(result?["ok"] as? Bool, true)
        XCTAssertEqual(result?["keyboard_ready"] as? Bool, true)
        XCTAssertEqual(result?["pointing_ready"] as? Bool, false)
    }

    func testClickActionDispatches() {
        let result = processJSON(["action": "click", "x": 100.0, "y": 200.0])
        XCTAssertEqual(result?["ok"] as? Bool, true)
    }
}
