// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for Karabiner wire protocol message construction: framing bytes, headers, payloads.
// ABOUTME: Verifies buildRequestMessage and buildHeartbeatMessage produce correct byte sequences.

import XCTest
import Foundation
import HelperLib
@testable import mirroir_helper

final class KarabinerWireProtocolTests: XCTestCase {

    // MARK: - buildRequestMessage

    func testRequestMessageFramingByte() {
        let message = KarabinerClient.buildRequestMessage(.none)
        XCTAssertFalse(message.isEmpty)
        // First byte is user_data type (0x01)
        XCTAssertEqual(message[0], 0x01)
    }

    func testRequestMessageHeader() {
        let message = KarabinerClient.buildRequestMessage(.none)
        XCTAssertGreaterThanOrEqual(message.count, 6)
        // Bytes 1,2 are 'c', 'p'
        XCTAssertEqual(message[1], 0x63) // 'c'
        XCTAssertEqual(message[2], 0x70) // 'p'
    }

    func testRequestMessageProtocolVersion() {
        let message = KarabinerClient.buildRequestMessage(.none)
        // Bytes 3,4 are protocol version 5 as LE uint16
        let version = UInt16(message[3]) | (UInt16(message[4]) << 8)
        XCTAssertEqual(version, 5)
    }

    func testRequestMessageRequestType() {
        let message = KarabinerClient.buildRequestMessage(.virtualHidKeyboardInitialize)
        // Byte 5 is the request type
        XCTAssertEqual(message[5], KarabinerRequest.virtualHidKeyboardInitialize.rawValue)
    }

    func testRequestMessagePayloadAppended() {
        let payload: [UInt8] = [0xAA, 0xBB, 0xCC]
        let message = KarabinerClient.buildRequestMessage(.postKeyboardInputReport, payload: payload)
        // Header is 6 bytes, payload follows
        XCTAssertEqual(message.count, 6 + payload.count)
        XCTAssertEqual(Array(message[6...]), payload)
    }

    func testRequestMessageNoPayload() {
        let message = KarabinerClient.buildRequestMessage(.virtualHidPointingInitialize)
        XCTAssertEqual(message.count, 6)
    }

    // MARK: - buildHeartbeatMessage

    func testHeartbeatFramingByte() {
        let message = KarabinerClient.buildHeartbeatMessage(deadlineMs: 5000)
        XCTAssertFalse(message.isEmpty)
        // First byte is heartbeat type (0x00)
        XCTAssertEqual(message[0], 0x00)
    }

    func testHeartbeatDeadlineEncoding() {
        let deadlineMs: UInt32 = 5000
        let message = KarabinerClient.buildHeartbeatMessage(deadlineMs: deadlineMs)
        XCTAssertEqual(message.count, 5)
        // Bytes 1-4 are deadline as LE uint32
        let decoded = UInt32(message[1])
            | (UInt32(message[2]) << 8)
            | (UInt32(message[3]) << 16)
            | (UInt32(message[4]) << 24)
        XCTAssertEqual(decoded, deadlineMs)
    }

    func testHeartbeatDifferentDeadline() {
        let deadlineMs: UInt32 = 10000
        let message = KarabinerClient.buildHeartbeatMessage(deadlineMs: deadlineMs)
        let decoded = UInt32(message[1])
            | (UInt32(message[2]) << 8)
            | (UInt32(message[3]) << 16)
            | (UInt32(message[4]) << 24)
        XCTAssertEqual(decoded, deadlineMs)
    }

    // MARK: - parseResponse

    func testParseResponseKeyboardReady() {
        let client = KarabinerClient()
        XCTAssertFalse(client.isKeyboardReady)

        // Simulate response: [0x01 (user_data)] [0x04 (virtualHidKeyboardReady)] [0x01 (ready=true)]
        let buf: [UInt8] = [0x01, KarabinerResponse.virtualHidKeyboardReady.rawValue, 0x01]
        try? client.parseResponse(buf: buf, bytesRead: buf.count)
        XCTAssertTrue(client.isKeyboardReady)
    }

    func testParseResponsePointingReady() {
        let client = KarabinerClient()
        XCTAssertFalse(client.isPointingReady)

        let buf: [UInt8] = [0x01, KarabinerResponse.virtualHidPointingReady.rawValue, 0x01]
        try? client.parseResponse(buf: buf, bytesRead: buf.count)
        XCTAssertTrue(client.isPointingReady)
    }

    func testParseResponseHeartbeat() {
        let client = KarabinerClient()
        // Heartbeat response should not crash or throw
        let buf: [UInt8] = [0x00]
        XCTAssertNoThrow(try client.parseResponse(buf: buf, bytesRead: buf.count))
    }

    func testParseResponseDriverVersionMismatch() {
        let client = KarabinerClient()
        // Response indicating version IS mismatched (buf[2] = 1)
        let buf: [UInt8] = [0x01, KarabinerResponse.driverVersionMismatched.rawValue, 0x01]
        XCTAssertThrowsError(try client.parseResponse(buf: buf, bytesRead: buf.count))
    }

    func testParseResponseDriverVersionNotMismatched() {
        let client = KarabinerClient()
        // Response indicating version is NOT mismatched (buf[2] = 0)
        let buf: [UInt8] = [0x01, KarabinerResponse.driverVersionMismatched.rawValue, 0x00]
        XCTAssertNoThrow(try client.parseResponse(buf: buf, bytesRead: buf.count))
    }
}
