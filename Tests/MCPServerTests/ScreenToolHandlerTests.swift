// ABOUTME: Tests for screen tool MCP handlers: screenshot, describe_screen, start/stop recording.
// ABOUTME: Verifies app-not-running checks, capture failure paths, and success responses.

import XCTest
import HelperLib
@testable import iphone_mirroir_mcp

final class ScreenToolHandlerTests: XCTestCase {

    private var server: MCPServer!
    private var bridge: StubBridge!
    private var capture: StubCapture!
    private var recorder: StubRecorder!
    private var describer: StubDescriber!

    override func setUp() {
        super.setUp()
        let policy = PermissionPolicy(skipPermissions: true, config: nil)
        server = MCPServer(policy: policy)
        bridge = StubBridge()
        capture = StubCapture()
        recorder = StubRecorder()
        describer = StubDescriber()
        IPhoneMirroirMCP.registerScreenTools(
            server: server, bridge: bridge, capture: capture,
            recorder: recorder, describer: describer
        )
    }

    private func callTool(_ name: String, args: [String: JSONValue] = [:]) -> JSONRPCResponse {
        let request = JSONRPCRequest(
            jsonrpc: "2.0", id: .number(1),
            method: "tools/call",
            params: .object([
                "name": .string(name),
                "arguments": .object(args),
            ])
        )
        return server.handleRequest(request)
    }

    private func extractText(_ response: JSONRPCResponse) -> String? {
        guard case .object(let result) = response.result,
              case .array(let content) = result["content"],
              case .object(let textObj) = content.first,
              case .string(let text) = textObj["text"] else { return nil }
        return text
    }

    private func isError(_ response: JSONRPCResponse) -> Bool {
        guard case .object(let result) = response.result,
              case .bool(let isErr) = result["isError"] else { return false }
        return isErr
    }

    // MARK: - screenshot

    func testScreenshotAppNotRunning() {
        bridge.processRunning = false
        let response = callTool("screenshot")
        XCTAssertTrue(isError(response))
        let text = extractText(response)
        XCTAssertTrue(text?.contains("not running") ?? false)
    }

    func testScreenshotCaptureFails() {
        bridge.processRunning = true
        capture.captureResult = nil
        let response = callTool("screenshot")
        XCTAssertTrue(isError(response))
        let text = extractText(response)
        XCTAssertTrue(text?.contains("Failed to capture") ?? false)
    }

    func testScreenshotSuccess() {
        bridge.processRunning = true
        capture.captureResult = "iVBORw0KGgo=" // minimal base64 PNG prefix
        let response = callTool("screenshot")
        XCTAssertFalse(isError(response))

        // Verify an image content block is returned
        guard case .object(let result) = response.result,
              case .array(let content) = result["content"],
              case .object(let imgObj) = content.first else {
            return XCTFail("Expected image content")
        }
        XCTAssertEqual(imgObj["type"], .string("image"))
        XCTAssertEqual(imgObj["data"], .string("iVBORw0KGgo="))
    }

    // MARK: - describe_screen

    func testDescribeScreenAppNotRunning() {
        bridge.processRunning = false
        let response = callTool("describe_screen")
        XCTAssertTrue(isError(response))
        let text = extractText(response)
        XCTAssertTrue(text?.contains("not running") ?? false)
    }

    func testDescribeScreenDescriberFails() {
        bridge.processRunning = true
        describer.describeResult = nil
        let response = callTool("describe_screen")
        XCTAssertTrue(isError(response))
        let text = extractText(response)
        XCTAssertTrue(text?.contains("Failed to capture") ?? false)
    }

    // MARK: - start_recording

    func testStartRecordingSuccess() {
        recorder.startResult = nil
        let response = callTool("start_recording")
        XCTAssertFalse(isError(response))
        XCTAssertEqual(extractText(response), "Recording started")
    }

    func testStartRecordingError() {
        recorder.startResult = "Permission denied"
        let response = callTool("start_recording")
        XCTAssertTrue(isError(response))
        XCTAssertEqual(extractText(response), "Permission denied")
    }

    // MARK: - stop_recording

    func testStopRecordingSuccess() {
        recorder.stopResult = ("/tmp/recording.mov", nil)
        let response = callTool("stop_recording")
        XCTAssertFalse(isError(response))
        XCTAssertEqual(extractText(response), "Recording saved to: /tmp/recording.mov")
    }

    func testStopRecordingError() {
        recorder.stopResult = (nil, "No recording in progress")
        let response = callTool("stop_recording")
        XCTAssertTrue(isError(response))
        XCTAssertEqual(extractText(response), "No recording in progress")
    }

    func testStopRecordingNoFile() {
        recorder.stopResult = (nil, nil)
        let response = callTool("stop_recording")
        XCTAssertTrue(isError(response))
        let text = extractText(response)
        XCTAssertTrue(text?.contains("no file") ?? false)
    }
}
