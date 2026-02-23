// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Shared enum of special key names for keyboard operations.
// ABOUTME: Used by AppleScriptKeyMap and CGEvent-based key press handling.

/// Canonical names for special (non-printable) keyboard keys.
/// Used as the key type for `AppleScriptKeyMap` (macOS virtual key codes)
/// and referenced by CGEvent key press operations.
public enum KeyName: String, CaseIterable, Sendable {
    case `return` = "return"
    case escape = "escape"
    case delete = "delete"
    case tab = "tab"
    case space = "space"
    case up = "up"
    case down = "down"
    case left = "left"
    case right = "right"

    /// All key names sorted alphabetically, for display in help text and error messages.
    public static var sortedNames: [String] {
        allCases.map(\.rawValue).sorted()
    }
}
