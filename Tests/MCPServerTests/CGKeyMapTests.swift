// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for CGKeyMap character-to-virtual-keycode mapping.
// ABOUTME: Verifies coverage of printable ASCII, dead-key sequences, and modifier flags.

import CoreGraphics
import Testing
@testable import mirroir_mcp

@Suite("CGKeyMap")
struct CGKeyMapTests {

    // MARK: - Coverage

    @Test("All printable ASCII characters have mappings")
    func allPrintableASCII() {
        // ASCII 32 (space) through 126 (~)
        var missing: [Character] = []
        for code in 32...126 {
            guard let scalar = UnicodeScalar(code) else { continue }
            let char = Character(scalar)
            if CGKeyMap.lookupSequence(char) == nil {
                missing.append(char)
            }
        }
        #expect(missing.isEmpty, "Missing mappings for: \(missing)")
    }

    @Test("Newline and tab have mappings")
    func specialWhitespace() {
        #expect(CGKeyMap.lookup(Character("\n")) != nil)
        #expect(CGKeyMap.lookup(Character("\t")) != nil)
        #expect(CGKeyMap.lookup(Character("\r")) != nil)
    }

    // MARK: - Letters

    @Test("Lowercase letters have no modifier flags")
    func lowercaseLetters() {
        for char in "abcdefghijklmnopqrstuvwxyz" {
            let mapping = CGKeyMap.lookup(char)
            #expect(mapping != nil, "Missing mapping for '\(char)'")
            #expect(mapping?.flags == CGEventFlags(), "'\(char)' should have no flags")
        }
    }

    @Test("Uppercase letters have shift flag")
    func uppercaseLetters() {
        for char in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            let mapping = CGKeyMap.lookup(char)
            #expect(mapping != nil, "Missing mapping for '\(char)'")
            #expect(mapping?.flags == .maskShift, "'\(char)' should have shift flag")
        }
    }

    @Test("Uppercase and lowercase share the same keycode")
    func caseSharesKeycode() {
        for (lower, upper) in zip("abcdefghijklmnopqrstuvwxyz", "ABCDEFGHIJKLMNOPQRSTUVWXYZ") {
            let lm = CGKeyMap.lookup(lower)
            let um = CGKeyMap.lookup(upper)
            #expect(lm?.keycode == um?.keycode, "'\(lower)' and '\(upper)' should share keycode")
        }
    }

    // MARK: - Digits

    @Test("Digits 0-9 have no modifier flags")
    func digits() {
        for char in "0123456789" {
            let mapping = CGKeyMap.lookup(char)
            #expect(mapping != nil, "Missing mapping for '\(char)'")
            #expect(mapping?.flags == CGEventFlags(), "'\(char)' should have no flags")
        }
    }

    @Test("Shifted digits have shift flag")
    func shiftedDigits() {
        for char in "!@#$%^&*()" {
            let mapping = CGKeyMap.lookup(char)
            #expect(mapping != nil, "Missing mapping for '\(char)'")
            #expect(mapping?.flags == .maskShift, "'\(char)' should have shift flag")
        }
    }

    // MARK: - Punctuation

    @Test("Unshifted punctuation has no modifier flags")
    func unshiftedPunctuation() {
        for char in "-=[]\\;',./`" {
            let mapping = CGKeyMap.lookup(char)
            #expect(mapping != nil, "Missing mapping for '\(char)'")
            #expect(mapping?.flags == CGEventFlags(), "'\(char)' should have no flags")
        }
    }

    @Test("Shifted punctuation has shift flag")
    func shiftedPunctuation() {
        for char in "_+{}|:\"<>?~" {
            let mapping = CGKeyMap.lookup(char)
            #expect(mapping != nil, "Missing mapping for '\(char)'")
            #expect(mapping?.flags == .maskShift, "'\(char)' should have shift flag")
        }
    }

    // MARK: - Dead-Key Sequences

    @Test("Accented characters produce 2-step sequences")
    func deadKeySequences() {
        let accented: [Character] = ["é", "è", "ü", "ê", "ñ", "á", "ö", "â", "ã", "î"]
        for char in accented {
            let sequence = CGKeyMap.lookupSequence(char)
            #expect(sequence != nil, "Missing sequence for '\(char)'")
            #expect(sequence?.steps.count == 2, "'\(char)' should have 2 steps, got \(sequence?.steps.count ?? 0)")
        }
    }

    @Test("Dead-key trigger step has Option flag")
    func deadKeyTriggerHasOption() {
        // é = Option+e, then e
        let sequence = CGKeyMap.lookupSequence(Character("é"))!
        let trigger = sequence.steps[0]
        #expect(trigger.flags.contains(.maskAlternate), "Dead-key trigger should have Option flag")
    }

    @Test("Uppercase accented characters have shift on base step")
    func uppercaseAccentedShift() {
        // É = Option+e, then Shift+e
        let sequence = CGKeyMap.lookupSequence(Character("É"))!
        #expect(sequence.steps.count == 2)
        let base = sequence.steps[1]
        #expect(base.flags.contains(.maskShift), "Uppercase accent base should have shift")
    }

    @Test("Direct Option characters have single-step sequence")
    func directOptionChars() {
        // ç = Option+c (single step)
        let sequence = CGKeyMap.lookupSequence(Character("ç"))
        #expect(sequence != nil)
        #expect(sequence?.steps.count == 1)
        #expect(sequence?.steps[0].flags.contains(.maskAlternate) ?? false)
    }

    @Test("Ç requires Option+Shift")
    func upperCedilla() {
        let sequence = CGKeyMap.lookupSequence(Character("Ç"))
        #expect(sequence != nil)
        #expect(sequence?.steps.count == 1)
        let flags = sequence!.steps[0].flags
        #expect(flags.contains(.maskAlternate))
        #expect(flags.contains(.maskShift))
    }

    // MARK: - Edge Cases

    @Test("Emoji returns nil")
    func emojiReturnsNil() {
        #expect(CGKeyMap.lookupSequence(Character("😀")) == nil)
    }

    @Test("CJK returns nil")
    func cjkReturnsNil() {
        #expect(CGKeyMap.lookupSequence(Character("漢")) == nil)
    }

    @Test("Count properties are consistent")
    func countProperties() {
        #expect(CGKeyMap.count > 90, "Should have >90 direct mappings")
        #expect(CGKeyMap.deadKeyCount > 30, "Should have >30 dead-key sequences")
    }

    @Test("lookupSequence wraps single-key lookup in 1-step sequence")
    func lookupSequenceWrapsSingle() {
        let mapping = CGKeyMap.lookup(Character("a"))!
        let sequence = CGKeyMap.lookupSequence(Character("a"))!
        #expect(sequence.steps.count == 1)
        #expect(sequence.steps[0].keycode == mapping.keycode)
        #expect(sequence.steps[0].flags == mapping.flags)
    }
}
