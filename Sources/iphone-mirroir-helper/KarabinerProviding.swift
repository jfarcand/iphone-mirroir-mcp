// ABOUTME: Protocol abstraction for the Karabiner virtual HID client.
// ABOUTME: Enables dependency injection for testing command handlers without real Karabiner hardware.

import Foundation
import HelperLib

/// Abstracts Karabiner virtual HID device operations for input simulation.
protocol KarabinerProviding: AnyObject {
    var isKeyboardReady: Bool { get }
    var isPointingReady: Bool { get }
    var isConnected: Bool { get }
    func postPointingReport(_ report: PointingInput)
    func postKeyboardReport(_ report: KeyboardInput)
    func typeKey(keycode: UInt16, modifiers: KeyboardModifier)
    func moveMouse(dx: Int8, dy: Int8)
    func click(button: UInt32)
    func releaseButtons()
}

extension KarabinerClient: KarabinerProviding {}
