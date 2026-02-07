// ABOUTME: Simulates user input (tap, swipe, keyboard) on the iPhone Mirroring window.
// ABOUTME: Delegates to the privileged Karabiner helper daemon for all DRM-protected input.

import CoreGraphics
import Foundation

/// Result of a type operation, including any characters the helper couldn't map.
struct TypeResult {
    let success: Bool
    let skippedCharacters: String
    let warning: String?
    let error: String?
}

/// Simulates touch and keyboard input on the iPhone Mirroring window.
/// All coordinates are relative to the mirroring window's content area.
///
/// Requires the Karabiner helper daemon for all input operations.
/// iPhone Mirroring uses a DRM-protected surface that blocks CGEvent input.
final class InputSimulation: @unchecked Sendable {
    private let bridge: MirroringBridge
    let helperClient = HelperClient()

    /// Reusable event source for pressKey (the only CGEvent-based operation).
    private let eventSource: CGEventSource?

    init(bridge: MirroringBridge) {
        self.bridge = bridge

        let source = CGEventSource(stateID: .hidSystemState)
        if let source {
            source.localEventsSuppressionInterval = 0.0
            source.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitLocalKeyboardEvents,
                 .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
        }
        self.eventSource = source
    }

    /// Tap at a position relative to the mirroring window.
    /// Returns nil on success, or an error message if the helper is unavailable.
    func tap(x: Double, y: Double) -> String? {
        guard let info = bridge.getWindowInfo() else {
            return "iPhone Mirroring window not found"
        }

        guard helperClient.isAvailable else {
            return helperClient.unavailableMessage
        }

        let screenX = info.position.x + CGFloat(x)
        let screenY = info.position.y + CGFloat(y)

        if helperClient.click(x: Double(screenX), y: Double(screenY)) {
            return nil // success
        }
        return "Helper click failed"
    }

    /// Swipe from one point to another relative to the mirroring window.
    /// Returns nil on success, or an error message if the helper is unavailable.
    func swipe(fromX: Double, fromY: Double, toX: Double, toY: Double, durationMs: Int = 300)
        -> String?
    {
        guard let info = bridge.getWindowInfo() else {
            return "iPhone Mirroring window not found"
        }

        guard helperClient.isAvailable else {
            return helperClient.unavailableMessage
        }

        let startX = Double(info.position.x) + fromX
        let startY = Double(info.position.y) + fromY
        let endX = Double(info.position.x) + toX
        let endY = Double(info.position.y) + toY

        if helperClient.swipe(fromX: startX, fromY: startY,
                              toX: endX, toY: endY,
                              durationMs: durationMs) {
            return nil // success
        }
        return "Helper swipe failed"
    }

    /// Type text by sending keyboard events via Karabiner virtual HID.
    /// Clicks the iPhone Mirroring title bar first to ensure keyboard focus.
    /// Returns a TypeResult with success status and any skipped characters.
    func typeText(_ text: String) -> TypeResult {
        guard helperClient.isAvailable else {
            return TypeResult(
                success: false, skippedCharacters: "",
                warning: nil, error: helperClient.unavailableMessage)
        }

        focusWindowViaClick()

        let result = helperClient.type(text: text)
        return TypeResult(
            success: result.ok,
            skippedCharacters: result.skippedCharacters,
            warning: result.warning,
            error: result.ok ? nil : "Helper type command failed")
    }

    /// Send a special key press (e.g., Return, Escape, Delete).
    /// Uses CGEvent directly — these work for menu-level keys even without the helper.
    func pressKey(_ keyCode: CGKeyCode) -> Bool {
        focusWindowViaClick()

        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        else { return false }

        keyDown.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    // MARK: - Private Helpers

    /// Give iPhone Mirroring keyboard focus by clicking its title bar.
    /// A click on the title bar makes the window the key window without
    /// triggering any iPhone touch input. More reliable than AX/AppleScript
    /// activation from a subprocess.
    private func focusWindowViaClick() {
        guard let info = bridge.getWindowInfo() else { return }

        // Click the center of the title bar (14 points below the top of the
        // window frame, which is above the iPhone content area).
        let titleBarX = Double(info.position.x) + Double(info.size.width) / 2.0
        let titleBarY = Double(info.position.y) + 14.0

        _ = helperClient.click(x: titleBarX, y: titleBarY)
        usleep(200_000) // 200ms for focus to settle
    }
}

// MARK: - Common Key Codes

enum KeyCode {
    static let returnKey: CGKeyCode = 36
    static let escape: CGKeyCode = 53
    static let delete: CGKeyCode = 51
    static let space: CGKeyCode = 49
    static let tab: CGKeyCode = 48
}
