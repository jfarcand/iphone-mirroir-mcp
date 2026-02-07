// ABOUTME: Packed C struct definitions for the Karabiner DriverKit virtual HID wire protocol.
// ABOUTME: Shared between the helper daemon (sends reports) and test targets (validates layout).

import Foundation

/// Keyboard initialization parameters (12 bytes, packed).
/// Matches virtual_hid_keyboard_parameters in parameters.hpp.
public struct KeyboardParameters: Sendable {
    public var vendorID: UInt32 = 0x16c0
    public var productID: UInt32 = 0x27db
    public var countryCode: UInt32 = 0

    public init() {}

    public func toBytes() -> [UInt8] {
        var copy = self
        return withUnsafeBytes(of: &copy) { Array($0) }
    }
}

/// Pointing device input report (8 bytes, packed).
/// Matches pointing_input in pointing_input.hpp.
public struct PointingInput: Sendable {
    public var buttons: UInt32 = 0
    public var x: Int8 = 0
    public var y: Int8 = 0
    public var verticalWheel: Int8 = 0
    public var horizontalWheel: Int8 = 0

    public init() {}

    public func toBytes() -> [UInt8] {
        var copy = self
        return withUnsafeBytes(of: &copy) { Array($0) }
    }
}

/// Keyboard input report (67 bytes, packed).
/// Matches keyboard_input in keyboard_input.hpp.
public struct KeyboardInput: Sendable {
    public var reportID: UInt8 = 1
    public var modifiers: UInt8 = 0
    public var reserved: UInt8 = 0
    public var keys: (
        UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16,
        UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16,
        UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16,
        UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16, UInt16
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0
    )

    public init() {}

    public mutating func insertKey(_ keyCode: UInt16) {
        withUnsafeMutableBytes(of: &keys) { buf in
            let keysPtr = buf.bindMemory(to: UInt16.self)
            for i in 0..<32 {
                if keysPtr[i] == 0 {
                    keysPtr[i] = keyCode
                    return
                }
            }
        }
    }

    public mutating func clearKeys() {
        keys = (
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0
        )
    }

    public func toBytes() -> [UInt8] {
        var copy = self
        return withUnsafeBytes(of: &copy) { Array($0) }
    }
}

/// Keyboard modifier flags matching the Karabiner modifier bitmask.
public struct KeyboardModifier: OptionSet, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let leftControl  = KeyboardModifier(rawValue: 0x01)
    public static let leftShift    = KeyboardModifier(rawValue: 0x02)
    public static let leftOption   = KeyboardModifier(rawValue: 0x04)
    public static let leftCommand  = KeyboardModifier(rawValue: 0x08)
    public static let rightControl = KeyboardModifier(rawValue: 0x10)
    public static let rightShift   = KeyboardModifier(rawValue: 0x20)
    public static let rightOption  = KeyboardModifier(rawValue: 0x40)
    public static let rightCommand = KeyboardModifier(rawValue: 0x80)
}
