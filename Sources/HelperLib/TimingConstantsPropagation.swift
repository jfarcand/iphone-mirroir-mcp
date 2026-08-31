// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Timing defaults for waits where the Mac acts and the device catches up.
// ABOUTME: Split from TimingConstants.swift to stay under the 500-line limit.

/// Waits on asynchronous propagation between the Mac and the mirrored device.
///
/// These differ in kind from the rest of ``TimingConstants``: the others pace
/// local event delivery, while each of these waits on something outside this
/// process — Continuity carrying the pasteboard, or the window server
/// compositing a frame the device has already drawn. Both fail silently when
/// too short, producing stale-but-plausible results rather than errors, which
/// is why their defaults are generous.
extension TimingConstants {
    /// Delay after CGWarpMouseCursorPosition for cursor to settle (microseconds).
    public static let cursorSettleUs: UInt32 = 10_000

    /// Hold duration for a standard click (microseconds).
    public static let clickHoldUs: UInt32 = 80_000

    /// Hold duration per tap in a double-tap gesture (microseconds).
    public static let doubleTapHoldUs: UInt32 = 40_000

    /// Gap between the two taps in a double-tap gesture (microseconds).
    public static let doubleTapGapUs: UInt32 = 50_000

    /// Initial hold before drag movement to trigger iOS drag recognition (microseconds).
    public static let dragModeHoldUs: UInt32 = 150_000

    /// Delay after focus click for keyboard focus to settle (microseconds).
    public static let focusSettleUs: UInt32 = 200_000

    /// Delay between individual keystrokes during typing (microseconds).
    public static let keystrokeDelayUs: UInt32 = 15_000

    /// Delay after writing the pasteboard before pressing Cmd+V (microseconds).
    ///
    /// This waits on Universal Clipboard, which carries the Mac pasteboard to
    /// the device over Continuity — not a local memcpy, and measured in seconds
    /// rather than milliseconds. It is also variable: at 120ms an emoji-only
    /// paste landed while a mixed-script paste issued moments earlier pasted the
    /// device's PREVIOUS clipboard value instead, silently producing wrong text.
    /// Losing that race is invisible — Cmd+V succeeds and pastes something — so
    /// the default is deliberately generous. There is no API to read the device
    /// pasteboard back and confirm, so waiting is the only lever.
    public static let pasteboardSyncUs: UInt32 = 1_500_000

    /// Delay after Cmd+V before the previous pasteboard contents are restored,
    /// so the paste is consumed before the clipboard changes underneath it
    /// (microseconds).
    public static let pasteCommitUs: UInt32 = 250_000

    /// Gap between successive captures while waiting for the screen to settle
    /// (microseconds). One mirroring frame at 60fps is ~16ms; polling slower
    /// than that avoids comparing two frames from the same refresh.
    public static let frameSettlePollUs: UInt32 = 60_000

    /// Longest a settled capture waits for two consecutive identical frames
    /// before returning the most recent one anyway (microseconds). A screen with
    /// a spinner, video, or blinking caret never settles, so this bounds the wait
    /// rather than failing.
    public static let frameSettleTimeoutUs: UInt32 = 1_500_000
}
