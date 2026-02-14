// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for the HID key mapping table covering all US QWERTY characters.
// ABOUTME: Validates keycodes and modifier flags against USB HID Usage Tables section 10.

import Testing
@testable import HelperLib

@Suite("HIDKeyMap")
struct HIDKeyMapTests {

    // MARK: - Lowercase Letters

    @Test("a-z map to HID 0x04-0x1D with no modifiers")
    func lowercaseLetters() {
        for (i, c) in "abcdefghijklmnopqrstuvwxyz".enumerated() {
            let mapping = HIDKeyMap.lookup(c)
            #expect(mapping != nil, "Missing mapping for '\(c)'")
            #expect(mapping!.keycode == UInt16(0x04 + i), "Wrong keycode for '\(c)'")
            #expect(mapping!.modifiers == [], "'\(c)' should have no modifiers")
        }
    }

    // MARK: - Uppercase Letters

    @Test("A-Z map to HID 0x04-0x1D with leftShift")
    func uppercaseLetters() {
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            let mapping = HIDKeyMap.lookup(c)
            #expect(mapping != nil, "Missing mapping for '\(c)'")
            #expect(mapping!.keycode == UInt16(0x04 + i), "Wrong keycode for '\(c)'")
            #expect(mapping!.modifiers == .leftShift, "'\(c)' should require leftShift")
        }
    }

    // MARK: - Digits

    @Test("0-9 map to HID 0x1E-0x27 with no modifiers")
    func digits() {
        // HID layout: 1=0x1E, 2=0x1F, ..., 9=0x26, 0=0x27
        let expected: [(Character, UInt16)] = [
            ("1", 0x1E), ("2", 0x1F), ("3", 0x20), ("4", 0x21), ("5", 0x22),
            ("6", 0x23), ("7", 0x24), ("8", 0x25), ("9", 0x26), ("0", 0x27),
        ]
        for (c, kc) in expected {
            let mapping = HIDKeyMap.lookup(c)
            #expect(mapping != nil, "Missing mapping for '\(c)'")
            #expect(mapping!.keycode == kc, "Wrong keycode for '\(c)': got \(mapping!.keycode), expected \(kc)")
            #expect(mapping!.modifiers == [], "'\(c)' should have no modifiers")
        }
    }

    // MARK: - Shifted Digits (Symbols)

    @Test("!@#$%^&*() map to digit keycodes with leftShift")
    func shiftedDigits() {
        let expected: [(Character, UInt16)] = [
            ("!", 0x1E), ("@", 0x1F), ("#", 0x20), ("$", 0x21), ("%", 0x22),
            ("^", 0x23), ("&", 0x24), ("*", 0x25), ("(", 0x26), (")", 0x27),
        ]
        for (c, kc) in expected {
            let mapping = HIDKeyMap.lookup(c)
            #expect(mapping != nil, "Missing mapping for '\(c)'")
            #expect(mapping!.keycode == kc, "Wrong keycode for '\(c)'")
            #expect(mapping!.modifiers == .leftShift, "'\(c)' should require leftShift")
        }
    }

    // MARK: - Whitespace

    @Test("space, newline, return, tab have correct keycodes")
    func whitespace() {
        let space = HIDKeyMap.lookup(" ")
        #expect(space?.keycode == 0x2C)
        #expect(space?.modifiers == [])

        let newline = HIDKeyMap.lookup("\n")
        #expect(newline?.keycode == 0x28)
        #expect(newline?.modifiers == [])

        let cr = HIDKeyMap.lookup("\r")
        #expect(cr?.keycode == 0x28)
        #expect(cr?.modifiers == [])

        let tab = HIDKeyMap.lookup("\t")
        #expect(tab?.keycode == 0x2B)
        #expect(tab?.modifiers == [])
    }

    // MARK: - Unshifted Punctuation

    @Test("unshifted punctuation has correct keycodes")
    func unshiftedPunctuation() {
        let expected: [(Character, UInt16)] = [
            ("-", 0x2D), ("=", 0x2E), ("[", 0x2F), ("]", 0x30), ("\\", 0x31),
            (";", 0x33), ("'", 0x34), ("`", 0x35), (",", 0x36), (".", 0x37),
            ("/", 0x38),
        ]
        for (c, kc) in expected {
            let mapping = HIDKeyMap.lookup(c)
            #expect(mapping != nil, "Missing mapping for '\(c)'")
            #expect(mapping!.keycode == kc, "Wrong keycode for '\(c)'")
            #expect(mapping!.modifiers == [], "'\(c)' should have no modifiers")
        }
    }

    // MARK: - Shifted Punctuation

    @Test("shifted punctuation requires leftShift and correct keycode")
    func shiftedPunctuation() {
        let expected: [(Character, UInt16)] = [
            ("_", 0x2D), ("+", 0x2E), ("{", 0x2F), ("}", 0x30), ("|", 0x31),
            (":", 0x33), ("\"", 0x34), ("~", 0x35), ("<", 0x36), (">", 0x37),
            ("?", 0x38),
        ]
        for (c, kc) in expected {
            let mapping = HIDKeyMap.lookup(c)
            #expect(mapping != nil, "Missing mapping for '\(c)'")
            #expect(mapping!.keycode == kc, "Wrong keycode for '\(c)'")
            #expect(mapping!.modifiers == .leftShift, "'\(c)' should require leftShift")
        }
    }

    // MARK: - Unmapped Characters

    @Test("unmapped characters return nil")
    func unmappedCharacters() {
        #expect(HIDKeyMap.lookup("\u{00E9}") == nil) // é (accent)
        #expect(HIDKeyMap.lookup("\u{1F600}") == nil) // emoji
        #expect(HIDKeyMap.lookup("\u{00A3}") == nil)  // £ (pound sign)
        #expect(HIDKeyMap.lookup("\u{00F1}") == nil)  // ñ
    }

    // MARK: - Completeness

    @Test("shifted and unshifted pairs share the same keycode")
    func shiftedPairsShareKeycode() {
        let pairs: [(Character, Character)] = [
            ("-", "_"), ("=", "+"), ("[", "{"), ("]", "}"), ("\\", "|"),
            (";", ":"), ("'", "\""), ("`", "~"), (",", "<"), (".", ">"),
            ("/", "?"),
        ]
        for (unshifted, shifted) in pairs {
            let u = HIDKeyMap.lookup(unshifted)
            let s = HIDKeyMap.lookup(shifted)
            #expect(u != nil && s != nil, "Missing mapping for pair '\(unshifted)'/'\(shifted)'")
            #expect(u!.keycode == s!.keycode, "'\(unshifted)' and '\(shifted)' should share keycode")
            #expect(u!.modifiers == [], "'\(unshifted)' should be unshifted")
            #expect(s!.modifiers == .leftShift, "'\(shifted)' should be shifted")
        }
    }

    @Test("map covers all printable ASCII")
    func coversAllPrintableASCII() {
        // All printable ASCII (0x20-0x7E) except DEL
        var unmapped = [Character]()
        for scalar in (0x20...0x7E).compactMap(Unicode.Scalar.init) {
            let c = Character(scalar)
            if HIDKeyMap.lookup(c) == nil {
                unmapped.append(c)
            }
        }
        #expect(unmapped.isEmpty, "Unmapped printable ASCII: \(unmapped)")
    }
}
