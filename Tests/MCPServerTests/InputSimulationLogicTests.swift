// ABOUTME: Tests for InputSimulation pure-logic methods: validateBounds and buildTypeSegments.
// ABOUTME: These methods are testable without system APIs since they only process coordinates and strings.

import XCTest
import CoreGraphics
import HelperLib
@testable import iphone_mirroir_mcp

final class InputSimulationLogicTests: XCTestCase {

    // We need a real InputSimulation instance to test its methods.
    // The bridge is not used by validateBounds or buildTypeSegments.
    private var simulation: InputSimulation!

    override func setUp() {
        super.setUp()
        let bridge = MirroringBridge()
        simulation = InputSimulation(bridge: bridge)
    }

    // MARK: - validateBounds

    func testValidateBoundsInBounds() {
        let info = WindowInfo(
            windowID: 1, position: .zero,
            size: CGSize(width: 410, height: 898), pid: 1
        )
        let result = simulation.validateBounds(x: 200, y: 400, info: info, tag: "test")
        XCTAssertNil(result, "In-bounds coordinates should return nil")
    }

    func testValidateBoundsNegativeX() {
        let info = WindowInfo(
            windowID: 1, position: .zero,
            size: CGSize(width: 410, height: 898), pid: 1
        )
        let result = simulation.validateBounds(x: -1, y: 400, info: info, tag: "test")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("outside") ?? false)
    }

    func testValidateBoundsXExceedsWidth() {
        let info = WindowInfo(
            windowID: 1, position: .zero,
            size: CGSize(width: 410, height: 898), pid: 1
        )
        let result = simulation.validateBounds(x: 420, y: 400, info: info, tag: "test")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("outside") ?? false)
    }

    func testValidateBoundsYExceedsHeight() {
        let info = WindowInfo(
            windowID: 1, position: .zero,
            size: CGSize(width: 410, height: 898), pid: 1
        )
        let result = simulation.validateBounds(x: 200, y: 900, info: info, tag: "test")
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("outside") ?? false)
    }

    func testValidateBoundsAtEdge() {
        let info = WindowInfo(
            windowID: 1, position: .zero,
            size: CGSize(width: 410, height: 898), pid: 1
        )
        // Exactly at bounds should be valid
        let result = simulation.validateBounds(x: 410, y: 898, info: info, tag: "test")
        XCTAssertNil(result, "Coordinates at exactly the boundary should be valid")
    }

    // MARK: - buildTypeSegments

    func testBuildTypeSegmentsAllHID() {
        let segments = simulation.buildTypeSegments("hello")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.method, .hid)
        XCTAssertEqual(segments.first?.text, "hello")
    }

    func testBuildTypeSegmentsEmptyString() {
        let segments = simulation.buildTypeSegments("")
        XCTAssertTrue(segments.isEmpty)
    }
}
