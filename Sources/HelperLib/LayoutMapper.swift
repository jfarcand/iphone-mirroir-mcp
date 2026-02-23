// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Translates characters between keyboard layouts using macOS UCKeyTranslate.
// ABOUTME: Builds substitution tables so US QWERTY virtual keycodes produce correct characters on non-US layouts.

import Carbon
import Foundation

/// Translates characters between keyboard layouts.
///
/// When the iPhone's hardware keyboard layout differs from US QWERTY, the same
/// virtual keycode produces different characters. This mapper uses `UCKeyTranslate`
/// to build a character substitution table: for each physical key, it compares what
/// US QWERTY produces vs what the target layout produces, then maps target→US so
/// CGEvent sends the right keycode.
public enum LayoutMapper {

    /// Get the `UCKeyboardLayout` data for a keyboard input source by its TIS source ID.
    /// Example source IDs: "com.apple.keylayout.US", "com.apple.keylayout.Canadian-CSA"
    ///
    /// Uses `includeAllInstalled=true` to access macOS-bundled layouts that aren't
    /// currently enabled in the user's input source preferences.
    public static func layoutData(forSourceID sourceID: String) -> Data? {
        let properties: NSDictionary = [
            kTISPropertyInputSourceID as String: sourceID
        ]
        guard let sourceList = TISCreateInputSourceList(properties, true),
              let sources = sourceList.takeRetainedValue() as? [TISInputSource],
              let source = sources.first
        else {
            return nil
        }
        return extractLayoutData(from: source)
    }

    /// Find the iPhone's keyboard layout for character translation.
    ///
    /// Reads the layout name from `EnvConfig.keyboardLayout` which resolves
    /// from settings.json (set by `mirroir-mcp configure`) or the
    /// `IPHONE_KEYBOARD_LAYOUT` environment variable.
    ///
    /// Pass an explicit `layout` to override config lookup (used by tests).
    /// Returns nil when the layout is empty or "US" (no substitution needed).
    public static func findNonUSLayout(layout override: String? = nil) -> (sourceID: String, layoutData: Data)? {
        let layout = override ?? EnvConfig.keyboardLayout
        guard !layout.isEmpty else { return nil }

        let fullID = layout.hasPrefix("com.apple.keylayout.")
            ? layout
            : "com.apple.keylayout.\(layout)"
        return layoutData(forSourceID: fullID).map { (fullID, $0) }
    }

    /// Build a character substitution table between US QWERTY and a target layout.
    ///
    /// For each virtual keycode and modifier state (unshifted / shifted), translates
    /// the keycode through both layouts. When the characters differ, records
    /// `targetChar → usChar` so that sending `usChar` via CGEvent produces
    /// `targetChar` on the iPhone.
    public static func buildSubstitution(
        usLayoutData: Data, targetLayoutData: Data
    ) -> [Character: Character] {
        var map = [Character: Character]()

        // Modifier states: no modifier and shift.
        // These match what CGKeyMap supports (unshifted + shifted).
        let modifierStates: [UInt32] = [
            0,  // no modifiers
            2,  // shift (Carbon shiftKey=0x200, shifted right 8 = 2)
        ]

        // Virtual keycodes 0-50 cover all main keyboard alphanumeric and punctuation keys.
        for keycode: UInt16 in 0...50 {
            for modState in modifierStates {
                guard let usChar = translateKeycode(
                    keycode, modifiers: modState, layoutData: usLayoutData
                ),
                    let targetChar = translateKeycode(
                        keycode, modifiers: modState, layoutData: targetLayoutData
                    )
                else { continue }

                if usChar != targetChar {
                    map[targetChar] = usChar
                }
            }
        }

        // iOS interprets HID 0x64 (ISO section key) and HID 0x35 (grave accent)
        // swapped compared to macOS for non-US layouts. Swap the substitution
        // values for the characters on these two keys so the correct HID keycode
        // reaches the iPhone.
        applyISOKeySwap(&map, usLayoutData: usLayoutData,
                         targetLayoutData: targetLayoutData)

        return map
    }

    /// Correct the ISO section key swap between macOS and iOS.
    ///
    /// macOS virtual keycode 0x0A (HID 0x64, ISO section key) and 0x32
    /// (HID 0x35, grave accent) produce different characters on the Mac vs
    /// the iPhone for non-US layouts. The iPhone effectively swaps these two
    /// physical keys. This detects substitution entries originating from these
    /// keycodes and swaps their US QWERTY targets.
    private static func applyISOKeySwap(
        _ map: inout [Character: Character],
        usLayoutData: Data, targetLayoutData: Data
    ) {
        let modifierStates: [UInt32] = [0, 2]

        for modState in modifierStates {
            guard let usSectionChar = translateKeycode(
                        0x0A, modifiers: modState, layoutData: usLayoutData),
                  let usGraveChar = translateKeycode(
                        0x32, modifiers: modState, layoutData: usLayoutData),
                  let targetSectionChar = translateKeycode(
                        0x0A, modifiers: modState, layoutData: targetLayoutData),
                  let targetGraveChar = translateKeycode(
                        0x32, modifiers: modState, layoutData: targetLayoutData)
            else { continue }

            // Only swap when both characters are in the substitution table
            // with the expected values from the Mac layout scan.
            if map[targetSectionChar] == usSectionChar
                && map[targetGraveChar] == usGraveChar
            {
                map[targetSectionChar] = usGraveChar
                map[targetGraveChar] = usSectionChar
            }
        }
    }

    /// Apply a substitution table to translate text.
    /// Characters not in the table pass through unchanged.
    public static func translate(
        _ text: String, substitution: [Character: Character]
    ) -> String {
        if substitution.isEmpty { return text }
        return String(text.map { substitution[$0] ?? $0 })
    }

    /// Translate a single virtual keycode + modifier state to a character
    /// using the provided keyboard layout data.
    ///
    /// Uses `kUCKeyTranslateNoDeadKeysMask` to get the immediate character
    /// without dead-key composition.
    public static func translateKeycode(
        _ keycode: UInt16, modifiers: UInt32, layoutData: Data
    ) -> Character? {
        return layoutData.withUnsafeBytes { buffer in
            guard let layoutPtr = buffer.baseAddress?
                .assumingMemoryBound(to: UCKeyboardLayout.self)
            else {
                return nil
            }

            var deadKeyState: UInt32 = 0
            var chars = [UniChar](repeating: 0, count: 4)
            var length: Int = 0

            // Keyboard type 0 (ANSI default) works for all standard layouts.
            // LMGetKbdType() reads low-memory globals that may not be initialized
            // in headless/test contexts.
            let status = UCKeyTranslate(
                layoutPtr,
                keycode,
                UInt16(kUCKeyActionDown),
                modifiers,
                0,
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )

            guard status == noErr, length > 0 else { return nil }
            let str = String(utf16CodeUnits: chars, count: length)
            return str.first
        }
    }

    // MARK: - Private

    /// Extract UCKeyboardLayout data from a TIS input source.
    private static func extractLayoutData(from source: TISInputSource) -> Data? {
        guard let rawPtr = TISGetInputSourceProperty(
            source, kTISPropertyUnicodeKeyLayoutData
        ) else {
            return nil
        }
        let cfData = Unmanaged<CFData>.fromOpaque(rawPtr).takeUnretainedValue()
        return cfData as Data
    }
}
