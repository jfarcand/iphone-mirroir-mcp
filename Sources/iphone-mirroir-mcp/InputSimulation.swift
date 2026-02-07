// ABOUTME: Simulates user input (tap, swipe, keyboard) on the iPhone Mirroring window.
// ABOUTME: Delegates to the privileged Karabiner helper daemon for all DRM-protected input.

import AppKit
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

    /// Type text using AppleScript keystroke via System Events.
    /// First activates iPhone Mirroring to make it the frontmost app,
    /// then sends keystrokes through System Events which routes to the frontmost app.
    func typeText(_ text: String) -> TypeResult {
        // Escape special AppleScript characters in the text
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let script = NSAppleScript(source: """
            tell application "System Events"
                tell process "iPhone Mirroring"
                    set frontmost to true
                end tell
                delay 0.5
                keystroke "\(escaped)"
            end tell
            """)

        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)

        if let err = errorInfo {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "AppleScript error"
            return TypeResult(success: false, skippedCharacters: "",
                              warning: nil, error: msg)
        }

        return TypeResult(success: true, skippedCharacters: "",
                          warning: nil, error: nil)
    }

    /// Send a special key press (e.g., Return, Escape, Delete).
    /// Uses CGEvent directly — these work for menu-level keys even without the helper.
    func pressKey(_ keyCode: CGKeyCode) -> Bool {
        bridge.activate()
        clickTitleBarViaCGEvent()

        guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: false)
        else { return false }

        keyDown.post(tap: .cghidEventTap)
        usleep(50_000)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    // MARK: - Private Helpers

    /// Give iPhone Mirroring keyboard focus by clicking its title bar via CGEvent.
    /// Uses in-process CGEvent (no IPC to the helper) so focus is acquired immediately.
    /// The title bar is regular macOS UI (not DRM-protected), so CGEvent clicks work here.
    private func clickTitleBarViaCGEvent() {
        guard let info = bridge.getWindowInfo() else { return }

        // Click the center of the title bar (14 points below the top of the
        // window frame, which is above the iPhone content area).
        let titleBarX = CGFloat(info.position.x) + info.size.width / 2.0
        let titleBarY = CGFloat(info.position.y) + 14.0
        let point = CGPoint(x: titleBarX, y: titleBarY)

        guard let mouseDown = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown,
                                      mouseCursorPosition: point, mouseButton: .left),
              let mouseUp = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp,
                                    mouseCursorPosition: point, mouseButton: .left)
        else { return }

        mouseDown.post(tap: .cghidEventTap)
        usleep(50_000) // 50ms click hold
        mouseUp.post(tap: .cghidEventTap)
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
