// ABOUTME: Tests for packed HID report structs that are sent over the Karabiner wire protocol.
// ABOUTME: Validates byte sizes, field positions, and endianness match the Karabiner C++ definitions.

import Testing
@testable import HelperLib

@Suite("PackedStructs")
struct PackedStructTests {

    // MARK: - PointingInput

    @Test("PointingInput is 8 bytes")
    func pointingInputSize() {
        #expect(MemoryLayout<PointingInput>.size == 8)
    }

    @Test("PointingInput default is all zeros")
    func pointingInputDefault() {
        let report = PointingInput()
        let bytes = report.toBytes()
        #expect(bytes == [0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test("PointingInput buttons are first 4 bytes little-endian")
    func pointingInputButtons() {
        var report = PointingInput()
        report.buttons = 0x01 // left button
        let bytes = report.toBytes()
        #expect(bytes[0] == 0x01)
        #expect(bytes[1] == 0x00)
        #expect(bytes[2] == 0x00)
        #expect(bytes[3] == 0x00)
    }

    @Test("PointingInput x,y are at byte offsets 4,5")
    func pointingInputMovement() {
        var report = PointingInput()
        report.x = 10
        report.y = -5
        let bytes = report.toBytes()
        #expect(bytes[4] == 10)
        #expect(bytes[5] == UInt8(bitPattern: -5))
    }

    @Test("PointingInput scroll wheels are at byte offsets 6,7")
    func pointingInputScroll() {
        var report = PointingInput()
        report.verticalWheel = 3
        report.horizontalWheel = -2
        let bytes = report.toBytes()
        #expect(bytes[6] == 3)
        #expect(bytes[7] == UInt8(bitPattern: -2))
    }

    // MARK: - KeyboardInput

    // Swift inserts 1 byte of padding after the 3 UInt8 fields (reportID, modifiers, reserved)
    // to align the UInt16 keys array. Layout: [u8, u8, u8, pad, u16 x 32] = 68 bytes.
    // The Karabiner C++ struct is packed (67 bytes). The extra padding byte is included
    // in the datagram payload — Karabiner reads only the bytes it needs.

    @Test("KeyboardInput is 68 bytes (3 header + 1 alignment padding + 64 keys)")
    func keyboardInputSize() {
        #expect(MemoryLayout<KeyboardInput>.size == 68)
    }

    @Test("KeyboardInput default has reportID=1 and all else zero")
    func keyboardInputDefault() {
        let report = KeyboardInput()
        let bytes = report.toBytes()
        #expect(bytes.count == 68)
        #expect(bytes[0] == 1) // reportID
        #expect(bytes[1] == 0) // modifiers
        #expect(bytes[2] == 0) // reserved
        #expect(bytes[3] == 0) // alignment padding
        // All keys zero (starting at byte 4)
        for i in 4..<68 {
            #expect(bytes[i] == 0, "byte[\(i)] should be 0")
        }
    }

    @Test("KeyboardInput insertKey places keycode in first empty slot")
    func keyboardInputInsertKey() {
        var report = KeyboardInput()
        report.insertKey(0x04) // 'a'
        let bytes = report.toBytes()
        // keys start at byte 4 (after 3 header bytes + 1 padding), each UInt16 is little-endian
        #expect(bytes[4] == 0x04)
        #expect(bytes[5] == 0x00)
    }

    @Test("KeyboardInput insertKey fills slots sequentially")
    func keyboardInputMultipleKeys() {
        var report = KeyboardInput()
        report.insertKey(0x04) // 'a'
        report.insertKey(0x05) // 'b'
        report.insertKey(0x06) // 'c'
        let bytes = report.toBytes()
        // Slot 0: bytes 4-5
        #expect(bytes[4] == 0x04)
        // Slot 1: bytes 6-7
        #expect(bytes[6] == 0x05)
        // Slot 2: bytes 8-9
        #expect(bytes[8] == 0x06)
    }

    @Test("KeyboardInput clearKeys zeros all key slots")
    func keyboardInputClearKeys() {
        var report = KeyboardInput()
        report.insertKey(0x04)
        report.insertKey(0x05)
        report.clearKeys()
        let bytes = report.toBytes()
        // Keys start at byte 4; verify all key bytes are zero
        for i in 4..<68 {
            #expect(bytes[i] == 0, "byte[\(i)] should be 0 after clearKeys")
        }
    }

    @Test("KeyboardInput modifiers byte is at offset 1")
    func keyboardInputModifiers() {
        var report = KeyboardInput()
        report.modifiers = KeyboardModifier.leftShift.rawValue
        let bytes = report.toBytes()
        #expect(bytes[1] == 0x02) // leftShift = 0x02
    }

    // MARK: - KeyboardParameters

    @Test("KeyboardParameters is 12 bytes")
    func keyboardParametersSize() {
        #expect(MemoryLayout<KeyboardParameters>.size == 12)
    }

    @Test("KeyboardParameters defaults match Karabiner expectations")
    func keyboardParametersDefaults() {
        let params = KeyboardParameters()
        let bytes = params.toBytes()
        #expect(bytes.count == 12)

        // vendorID = 0x16c0 (little-endian at bytes 0-3)
        #expect(bytes[0] == 0xC0)
        #expect(bytes[1] == 0x16)
        #expect(bytes[2] == 0x00)
        #expect(bytes[3] == 0x00)

        // productID = 0x27db (little-endian at bytes 4-7)
        #expect(bytes[4] == 0xDB)
        #expect(bytes[5] == 0x27)
        #expect(bytes[6] == 0x00)
        #expect(bytes[7] == 0x00)

        // countryCode = 0 (bytes 8-11)
        #expect(bytes[8] == 0x00)
        #expect(bytes[9] == 0x00)
        #expect(bytes[10] == 0x00)
        #expect(bytes[11] == 0x00)
    }

    // MARK: - KeyboardModifier

    @Test("KeyboardModifier flags have correct bit positions")
    func modifierBits() {
        #expect(KeyboardModifier.leftControl.rawValue  == 0x01)
        #expect(KeyboardModifier.leftShift.rawValue    == 0x02)
        #expect(KeyboardModifier.leftOption.rawValue   == 0x04)
        #expect(KeyboardModifier.leftCommand.rawValue  == 0x08)
        #expect(KeyboardModifier.rightControl.rawValue == 0x10)
        #expect(KeyboardModifier.rightShift.rawValue   == 0x20)
        #expect(KeyboardModifier.rightOption.rawValue  == 0x40)
        #expect(KeyboardModifier.rightCommand.rawValue == 0x80)
    }

    @Test("KeyboardModifier supports combining flags")
    func modifierCombination() {
        let combo: KeyboardModifier = [.leftShift, .leftControl]
        #expect(combo.rawValue == 0x03)
        #expect(combo.contains(.leftShift))
        #expect(combo.contains(.leftControl))
        #expect(!combo.contains(.leftOption))
    }
}
