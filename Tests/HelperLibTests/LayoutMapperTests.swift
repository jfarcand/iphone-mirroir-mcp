// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for keyboard layout translation using UCKeyTranslate.
// ABOUTME: Validates substitution table construction, character translation, and US QWERTY keycode mapping.

import Darwin
import Foundation
import Testing
@testable import HelperLib

// TIS (Text Input Source) APIs are not thread-safe — concurrent calls crash.
// Swift-testing runs tests in parallel, so this suite must be serialized.
@Suite("LayoutMapper", .serialized)
struct LayoutMapperTests {

    // MARK: - Translate

    @Test("translate passes through text when substitution is empty")
    func translateEmptySubstitution() {
        let text = "Hello, World! /path/to/file"
        let result = LayoutMapper.translate(text, substitution: [:])
        #expect(result == text)
    }

    @Test("translate applies character substitution")
    func translateAppliesSubstitution() {
        let substitution: [Character: Character] = [
            "/": "?",
            ".": ">",
        ]
        let result = LayoutMapper.translate("a/b.c", substitution: substitution)
        #expect(result == "a?b>c")
    }

    @Test("translate preserves characters not in substitution table")
    func translatePreservesUnmappedChars() {
        let substitution: [Character: Character] = ["x": "y"]
        let result = LayoutMapper.translate("hello x world", substitution: substitution)
        #expect(result == "hello y world")
    }

    // MARK: - US QWERTY Layout Data

    @Test("US QWERTY layout data is accessible")
    func usLayoutDataExists() {
        let data = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US")
        #expect(data != nil, "US QWERTY layout data should always be available on macOS")
    }

    // MARK: - UCKeyTranslate with US QWERTY

    @Test("translateKeycode produces correct US QWERTY letters")
    func usQwertyLetters() {
        guard let usData = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US") else {
            Issue.record("US QWERTY layout data not found")
            return
        }

        // Virtual keycode 0x00 = 'a' on US QWERTY (no modifier)
        let a = LayoutMapper.translateKeycode(0x00, modifiers: 0, layoutData: usData)
        #expect(a == "a")

        // Virtual keycode 0x00 = 'A' on US QWERTY (shift)
        let shiftA = LayoutMapper.translateKeycode(0x00, modifiers: 2, layoutData: usData)
        #expect(shiftA == "A")
    }

    @Test("translateKeycode produces correct US QWERTY digits")
    func usQwertyDigits() {
        guard let usData = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US") else {
            Issue.record("US QWERTY layout data not found")
            return
        }

        // Virtual keycode 0x12 = '1' key on US QWERTY
        let one = LayoutMapper.translateKeycode(0x12, modifiers: 0, layoutData: usData)
        #expect(one == "1")

        // Virtual keycode 0x12 + shift = '!' on US QWERTY
        let excl = LayoutMapper.translateKeycode(0x12, modifiers: 2, layoutData: usData)
        #expect(excl == "!")
    }

    @Test("translateKeycode produces correct US QWERTY punctuation")
    func usQwertyPunctuation() {
        guard let usData = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US") else {
            Issue.record("US QWERTY layout data not found")
            return
        }

        // Virtual keycode 0x2C = '/' on US QWERTY
        let slash = LayoutMapper.translateKeycode(0x2C, modifiers: 0, layoutData: usData)
        #expect(slash == "/")

        // Virtual keycode 0x2F = '.' on US QWERTY
        let dot = LayoutMapper.translateKeycode(0x2F, modifiers: 0, layoutData: usData)
        #expect(dot == ".")
    }

    // MARK: - Substitution Table Construction

    @Test("same layout produces empty substitution table")
    func sameLayoutEmptySubstitution() {
        guard let usData = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US") else {
            Issue.record("US QWERTY layout data not found")
            return
        }

        let substitution = LayoutMapper.buildSubstitution(
            usLayoutData: usData, targetLayoutData: usData
        )
        #expect(substitution.isEmpty, "Same layout should produce no substitutions")
    }

    @Test("Canadian-CSA layout produces substitutions for accented characters")
    func canadianCSASubstitution() {
        guard let usData = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US") else {
            Issue.record("US QWERTY layout data not found")
            return
        }

        guard let csaData = LayoutMapper.layoutData(
            forSourceID: "com.apple.keylayout.Canadian-CSA"
        ) else {
            Issue.record("Canadian-CSA layout data not found")
            return
        }

        let substitution = LayoutMapper.buildSubstitution(
            usLayoutData: usData, targetLayoutData: csaData
        )
        #expect(!substitution.isEmpty,
                "Canadian-CSA should differ from US QWERTY")
        #expect(substitution.count >= 10,
                "Canadian-CSA should have at least 10 substitutions, got \(substitution.count)")

        // The / key on US QWERTY (vk 0x2C) produces é on Canadian-CSA.
        // To type é on iPhone, send / to the helper.
        #expect(substitution[Character("é")] == Character("/"),
                "é should map to / for Canadian-CSA")

        // After ISO key swap: / maps to ` (HID 0x35) instead of § (HID 0x64)
        // because iOS swaps the ISO section key and grave accent key.
        #expect(substitution[Character("/")] == Character("`"),
                "/ should map to ` after ISO key swap")
    }

    // MARK: - findNonUSLayout (env var gating)

    @Test("findNonUSLayout returns nil when env var is not set")
    func findNonUSLayoutDefaultReturnsNil() {
        let saved = ProcessInfo.processInfo.environment["IPHONE_KEYBOARD_LAYOUT"]
        unsetenv("IPHONE_KEYBOARD_LAYOUT")
        defer {
            if let saved { setenv("IPHONE_KEYBOARD_LAYOUT", saved, 1) }
            else { unsetenv("IPHONE_KEYBOARD_LAYOUT") }
        }

        let result = LayoutMapper.findNonUSLayout()
        #expect(result == nil, "Without env var, findNonUSLayout should return nil (US QWERTY default)")
    }

    @Test("findNonUSLayout returns layout when env var is set to Canadian-CSA")
    func findNonUSLayoutWithCanadianCSA() {
        let saved = ProcessInfo.processInfo.environment["IPHONE_KEYBOARD_LAYOUT"]
        setenv("IPHONE_KEYBOARD_LAYOUT", "Canadian-CSA", 1)
        defer {
            if let saved { setenv("IPHONE_KEYBOARD_LAYOUT", saved, 1) }
            else { unsetenv("IPHONE_KEYBOARD_LAYOUT") }
        }

        let result = LayoutMapper.findNonUSLayout()
        #expect(result != nil, "With IPHONE_KEYBOARD_LAYOUT=Canadian-CSA, should return layout data")
        #expect(result?.sourceID == "com.apple.keylayout.Canadian-CSA")
    }

    @Test("findNonUSLayout accepts full source ID in env var")
    func findNonUSLayoutWithFullSourceID() {
        let saved = ProcessInfo.processInfo.environment["IPHONE_KEYBOARD_LAYOUT"]
        setenv("IPHONE_KEYBOARD_LAYOUT", "com.apple.keylayout.Canadian-CSA", 1)
        defer {
            if let saved { setenv("IPHONE_KEYBOARD_LAYOUT", saved, 1) }
            else { unsetenv("IPHONE_KEYBOARD_LAYOUT") }
        }

        let result = LayoutMapper.findNonUSLayout()
        #expect(result != nil, "Full source ID should be accepted")
        #expect(result?.sourceID == "com.apple.keylayout.Canadian-CSA")
    }

    @Test("findNonUSLayout returns nil for unknown layout name")
    func findNonUSLayoutWithUnknownLayout() {
        let saved = ProcessInfo.processInfo.environment["IPHONE_KEYBOARD_LAYOUT"]
        setenv("IPHONE_KEYBOARD_LAYOUT", "Nonexistent-Layout-XYZ", 1)
        defer {
            if let saved { setenv("IPHONE_KEYBOARD_LAYOUT", saved, 1) }
            else { unsetenv("IPHONE_KEYBOARD_LAYOUT") }
        }

        let result = LayoutMapper.findNonUSLayout()
        #expect(result == nil, "Unknown layout should return nil")
    }

    @Test("US QWERTY produces empty substitution (no-op when iPhone uses US)")
    func usLayoutProducesEmptySubstitution() {
        guard let usData = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US") else {
            Issue.record("US QWERTY layout data not found")
            return
        }

        // When IPHONE_KEYBOARD_LAYOUT=US, buildSubstitution(us, us) should be empty.
        // This confirms the no-op behavior for US keyboard users.
        let substitution = LayoutMapper.buildSubstitution(
            usLayoutData: usData, targetLayoutData: usData
        )
        #expect(substitution.isEmpty,
                "US → US should produce no substitutions (slash types as slash)")
    }

    // MARK: - Round-Trip Consistency

    @Test("Canadian-CSA substitutions are all HID-typeable after ISO key swap")
    func substitutionHIDCoverage() {
        guard let usData = LayoutMapper.layoutData(forSourceID: "com.apple.keylayout.US"),
              let csaData = LayoutMapper.layoutData(
                  forSourceID: "com.apple.keylayout.Canadian-CSA")
        else {
            return
        }

        let substitution = LayoutMapper.buildSubstitution(
            usLayoutData: usData, targetLayoutData: csaData
        )

        // After the ISO key swap, all substituted US characters should be
        // in the typeable range (printable ASCII or known special characters).
        // The swap corrects the macOS/iOS disagreement on virtual keycodes 0x64
        // and 0x35, so characters like / and ù are both typeable.
        for (targetChar, usChar) in substitution {
            let scalar = usChar.unicodeScalars.first!.value
            let isTypeable = (scalar >= 0x20 && scalar <= 0x7E) || scalar == 0xA7 || scalar == 0xB1
            #expect(isTypeable,
                    "'\(targetChar)' → '\(usChar)' (U+\(String(scalar, radix: 16))) should be typeable")
        }
    }
}
