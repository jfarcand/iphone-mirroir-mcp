// ABOUTME: Stub Karabiner client for helper daemon unit tests.
// ABOUTME: Records calls and returns configurable values without real Karabiner hardware.

import Foundation
import HelperLib
@testable import iphone_mirroir_helper

final class StubKarabiner: KarabinerProviding {
    var isKeyboardReady = true
    var isPointingReady = true
    var isConnected = true

    var postedPointingReports: [PointingInput] = []
    var postedKeyboardReports: [KeyboardInput] = []
    var typedKeys: [(keycode: UInt16, modifiers: KeyboardModifier)] = []
    var movedDeltas: [(dx: Int8, dy: Int8)] = []
    var clickedButtons: [UInt32] = []
    var releasedCount = 0

    func postPointingReport(_ report: PointingInput) {
        postedPointingReports.append(report)
    }

    func postKeyboardReport(_ report: KeyboardInput) {
        postedKeyboardReports.append(report)
    }

    func typeKey(keycode: UInt16, modifiers: KeyboardModifier) {
        typedKeys.append((keycode: keycode, modifiers: modifiers))
    }

    func moveMouse(dx: Int8, dy: Int8) {
        movedDeltas.append((dx: dx, dy: dy))
    }

    func click(button: UInt32) {
        clickedButtons.append(button)
    }

    func releaseButtons() {
        releasedCount += 1
    }
}
