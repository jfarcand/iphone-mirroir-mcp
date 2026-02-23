// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: CGEvent-based input (click, scroll, drag, keyboard) for target windows.
// ABOUTME: Posts mouse and keyboard events directly via macOS CGEvent API.

import CoreGraphics
import Foundation

/// CGEvent-based input operations for pointing and keyboard.
/// iPhone Mirroring accepts physical mouse and keyboard input;
/// CGEvent posts into the same macOS event pipeline as physical devices.
enum CGEventInput {

    /// Milliseconds to pause between mouse-down and mouse-up for a click.
    private static let clickHoldUs: UInt32 = 50_000

    /// Milliseconds to settle after warping cursor before posting events.
    private static let warpSettleUs: UInt32 = 30_000

    /// Click (tap) at a screen-absolute point.
    static func click(at point: CGPoint) -> Bool {
        guard let down = makeMouseEvent(.leftMouseDown, at: point),
              let up = makeMouseEvent(.leftMouseUp, at: point) else {
            return false
        }

        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(0)
        defer { CGAssociateMouseAndMouseCursorPosition(1) }

        usleep(warpSettleUs)
        down.post(tap: .cghidEventTap)
        usleep(clickHoldUs)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Long press at a screen-absolute point for the specified duration.
    static func longPress(at point: CGPoint, durationMs: Int) -> Bool {
        guard let down = makeMouseEvent(.leftMouseDown, at: point),
              let up = makeMouseEvent(.leftMouseUp, at: point) else {
            return false
        }

        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(0)
        defer { CGAssociateMouseAndMouseCursorPosition(1) }

        usleep(warpSettleUs)
        down.post(tap: .cghidEventTap)
        usleep(UInt32(durationMs) * 1000)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Double-tap at a screen-absolute point.
    static func doubleTap(at point: CGPoint) -> Bool {
        guard let down1 = makeMouseEvent(.leftMouseDown, at: point),
              let up1 = makeMouseEvent(.leftMouseUp, at: point),
              let down2 = makeMouseEvent(.leftMouseDown, at: point),
              let up2 = makeMouseEvent(.leftMouseUp, at: point) else {
            return false
        }

        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(0)
        defer { CGAssociateMouseAndMouseCursorPosition(1) }

        // First click
        usleep(warpSettleUs)
        down1.setIntegerValueField(.mouseEventClickState, value: 1)
        down1.post(tap: .cghidEventTap)
        usleep(clickHoldUs)
        up1.setIntegerValueField(.mouseEventClickState, value: 1)
        up1.post(tap: .cghidEventTap)

        // Brief inter-click pause (under the double-click threshold)
        usleep(clickHoldUs)

        // Second click with clickState=2 so macOS treats it as a double-click
        down2.setIntegerValueField(.mouseEventClickState, value: 2)
        down2.post(tap: .cghidEventTap)
        usleep(clickHoldUs)
        up2.setIntegerValueField(.mouseEventClickState, value: 2)
        up2.post(tap: .cghidEventTap)
        return true
    }

    /// Swipe (scroll wheel) from one screen-absolute point to another.
    /// Uses scroll wheel events since iPhone Mirroring interprets scroll
    /// wheel as swipe gestures (page scrolling, list scrolling).
    static func swipe(from start: CGPoint, to end: CGPoint, durationMs: Int) -> Bool {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y

        // Post scroll at the midpoint so it's within the window
        let midpoint = CGPoint(x: start.x + deltaX / 2, y: start.y + deltaY / 2)

        CGWarpMouseCursorPosition(midpoint)
        CGAssociateMouseAndMouseCursorPosition(0)
        defer { CGAssociateMouseAndMouseCursorPosition(1) }

        usleep(warpSettleUs)

        // Split into steps for a smooth scroll gesture
        let steps = max(5, durationMs / 16) // ~60fps step rate
        let stepDelay = UInt32(durationMs) * 1000 / UInt32(steps)

        // Scroll wheel: positive wheel1 = scroll up (content moves down),
        // negative wheel1 = scroll down (content moves up).
        // A swipe from top to bottom (positive deltaY) means the user
        // dragged downward, which in scroll-wheel terms is scroll-up (positive).
        let totalWheel1 = Int32(deltaY)
        let totalWheel2 = Int32(-deltaX) // horizontal: right-swipe = scroll left

        for i in 1...steps {
            // Compute incremental delta for this step
            let prevFraction = Double(i - 1) / Double(steps)
            let fraction = Double(i) / Double(steps)
            let w1 = Int32(Double(totalWheel1) * fraction) - Int32(Double(totalWheel1) * prevFraction)
            let w2 = Int32(Double(totalWheel2) * fraction) - Int32(Double(totalWheel2) * prevFraction)

            guard let scroll = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: w1,
                wheel2: w2,
                wheel3: 0
            ) else { continue }
            scroll.location = midpoint
            scroll.post(tap: .cghidEventTap)
            usleep(stepDelay)
        }
        return true
    }

    /// Drag (sustained mouse contact) from one screen-absolute point to another.
    /// Uses click-drag events (not scroll wheel) for rearranging icons,
    /// adjusting sliders, and drag-and-drop operations.
    static func drag(from start: CGPoint, to end: CGPoint, durationMs: Int) -> Bool {
        guard let down = makeMouseEvent(.leftMouseDown, at: start),
              let up = makeMouseEvent(.leftMouseUp, at: end) else {
            return false
        }

        CGWarpMouseCursorPosition(start)
        CGAssociateMouseAndMouseCursorPosition(0)
        defer { CGAssociateMouseAndMouseCursorPosition(1) }

        usleep(warpSettleUs)
        down.post(tap: .cghidEventTap)

        // Interpolate drag movement
        let steps = max(10, durationMs / 16) // ~60fps
        let stepDelay = UInt32(durationMs) * 1000 / UInt32(steps)

        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = start.x + (end.x - start.x) * t
            let y = start.y + (end.y - start.y) * t
            let point = CGPoint(x: x, y: y)

            guard let dragEvent = makeMouseEvent(.leftMouseDragged, at: point) else { continue }
            dragEvent.post(tap: .cghidEventTap)
            usleep(stepDelay)
        }

        up.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Keyboard

    /// Microseconds to pause between consecutive keystrokes.
    private static let keystrokeDelayUs: UInt32 = 8_000

    /// Microseconds to pause between dead-key trigger and base character.
    private static let deadKeyDelayUs: UInt32 = 30_000

    /// Post a single key event (key-down + key-up) with modifier flags.
    /// Returns true if the events were created and posted successfully.
    static func postKey(keycode: UInt16, flags: CGEventFlags = CGEventFlags()) -> Bool {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: false) else {
            return false
        }

        down.flags = flags
        up.flags = flags

        down.post(tap: .cghidEventTap)
        usleep(keystrokeDelayUs)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Post a dead-key sequence (2+ key events with a longer delay between them).
    /// Used for accented characters like é (Option+e, then e).
    static func postKeySequence(_ sequence: CGKeySequence) -> Bool {
        for (index, step) in sequence.steps.enumerated() {
            guard postKey(keycode: step.keycode, flags: step.flags) else {
                return false
            }
            // Use longer delay after the dead-key trigger (first step),
            // shorter delay after subsequent steps.
            if index < sequence.steps.count - 1 {
                usleep(deadKeyDelayUs)
            }
        }
        return true
    }

    /// Trigger a shake gesture by posting Ctrl+Cmd+Z via CGEvent.
    static func shake() -> Bool {
        let flags: CGEventFlags = [.maskControl, .maskCommand]
        // Z key = kVK_ANSI_Z = 0x06
        return postKey(keycode: 0x06, flags: flags)
    }

    // MARK: - Private

    /// Create a CGEvent for the given mouse event type at the specified position.
    private static func makeMouseEvent(
        _ type: CGEventType, at point: CGPoint
    ) -> CGEvent? {
        CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        )
    }
}
