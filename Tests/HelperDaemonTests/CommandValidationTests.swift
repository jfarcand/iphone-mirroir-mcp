// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for command parameter validation in the helper daemon handlers.
// ABOUTME: Verifies missing-param errors, device-not-ready checks, and default/minimum value clamping.

import XCTest
import Foundation
import HelperLib
@testable import iphone_mirroir_helper

final class CommandValidationTests: XCTestCase {

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

    // MARK: - click

    func testClickMissingX() {
        let result = processJSON(["action": "click", "y": 100])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("x and y"))
    }

    func testClickMissingY() {
        let result = processJSON(["action": "click", "x": 100])
        XCTAssertEqual(result?["ok"] as? Bool, false)
    }

    func testClickPointingNotReady() {
        karabiner.isPointingReady = false
        let result = processJSON(["action": "click", "x": 100, "y": 200])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("pointing device not ready"))
    }

    // MARK: - long_press

    func testLongPressMissingParams() {
        let result = processJSON(["action": "long_press"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("x and y"))
    }

    func testLongPressDefaultDuration() {
        // With pointing ready, long_press with x/y should succeed
        let result = processJSON(["action": "long_press", "x": 100, "y": 200])
        XCTAssertEqual(result?["ok"] as? Bool, true)
    }

    // MARK: - drag

    func testDragMissingParams() {
        let result = processJSON(["action": "drag", "from_x": 100])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("from_x, from_y, to_x, to_y"))
    }

    func testDragPointingNotReady() {
        karabiner.isPointingReady = false
        let result = processJSON([
            "action": "drag",
            "from_x": 100, "from_y": 200,
            "to_x": 150, "to_y": 250,
        ])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("pointing device not ready"))
    }

    // MARK: - swipe

    func testSwipeMissingParams() {
        let result = processJSON(["action": "swipe"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("from_x, from_y, to_x, to_y"))
    }

    // MARK: - move

    func testMoveMissingParams() {
        let result = processJSON(["action": "move"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("dx and dy"))
    }

    func testMovePointingNotReady() {
        karabiner.isPointingReady = false
        let result = processJSON(["action": "move", "dx": 1, "dy": 2])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("pointing device not ready"))
    }

    // MARK: - double_tap

    func testDoubleTapMissingParams() {
        let result = processJSON(["action": "double_tap"])
        XCTAssertEqual(result?["ok"] as? Bool, false)
        let error = result?["error"] as? String ?? ""
        XCTAssertTrue(error.contains("x and y"))
    }
}
