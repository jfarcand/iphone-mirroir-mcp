// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Bridge to the macOS iPhone Mirroring app (com.apple.ScreenContinuity).
// ABOUTME: Uses AXUIElement APIs to find the window, detect state, and trigger menu actions.

import AppKit
import ApplicationServices
import HelperLib

/// Device orientation based on mirroring window dimensions.
enum DeviceOrientation: String, Sendable {
    case portrait
    case landscape
}

/// Connection state of a target window (iPhone Mirroring or generic window).
enum WindowState: Sendable {
    case connected
    case paused
    case notRunning
    case noWindow
}

/// Backward-compatible alias for code that references the old name.
typealias MirroringState = WindowState

/// Information about the mirroring window position and size.
struct WindowInfo: Sendable {
    let windowID: CGWindowID
    let position: CGPoint
    let size: CGSize
    let pid: pid_t
}

/// Bridge to interact with the iPhone Mirroring app via macOS accessibility APIs.
/// The iPhone Mirroring window is special — it does not appear in AXWindows
/// but is accessible via AXMainWindow/AXFocusedWindow.
final class MirroringBridge: Sendable {
    let targetName: String
    private let bundleIdentifier: String

    init(targetName: String = "iphone",
         bundleID: String? = nil) {
        self.targetName = targetName
        self.bundleIdentifier = bundleID ?? EnvConfig.mirroringBundleID
    }

    /// Find the iPhone Mirroring process.
    ///
    /// Resolved live on every call via `RunningAppLocator`: a device respring
    /// restarts ScreenContinuity under a new PID, and the long-lived server must
    /// follow it rather than keep querying AX against the process that died.
    func findProcess() -> NSRunningApplication? {
        RunningAppLocator.byBundleID(bundleIdentifier)
    }

    /// Get the AXUIElement for the main mirroring window.
    func getMainWindow() -> (AXUIElement, pid_t)? {
        guard let app = findProcess() else { return nil }
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var windowValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            appRef, kAXMainWindowAttribute as CFString, &windowValue
        )
        guard result == .success,
              let window = windowValue,
              CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        // Safe cast: CFTypeID check above confirms the type
        let axWindow = unsafeDowncast(window, to: AXUIElement.self)
        return (axWindow, pid)
    }

    /// Get the window info including CGWindowID for screenshots.
    ///
    /// Prefers CGWindowList bounds over AX position because AX can lag the
    /// WindowServer's actual window position after scenario / focus switches
    /// (observed empirically on macos-15 CI runners — AX returned a stale
    /// position while CGEvent posting landed at the window's true location).
    /// CGWindowList reflects the compositor's authoritative bounds.
    func getWindowInfo() -> WindowInfo? {
        guard let (window, pid) = getMainWindow() else { return nil }

        guard let geom = WindowListHelper.geometryFromAXElement(window) else { return nil }

        let windowList = WindowListHelper.captureWindowList()
        let liveBounds = WindowListHelper.liveBoundsForPID(
            pid, axPosition: geom.position, axSize: geom.size, in: windowList
        )

        let resolved = liveBounds ?? (position: geom.position, size: geom.size, windowID: 0 as CGWindowID)

        return WindowInfo(
            windowID: resolved.windowID,
            position: resolved.position,
            size: resolved.size,
            pid: pid
        )
    }

    /// Detect the current mirroring connection state.
    func getState() -> MirroringState {
        guard findProcess() != nil else { return .notRunning }
        guard let (window, _) = getMainWindow() else { return .noWindow }

        // Check children of the window's hosting view
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement], let hostingView = kids.first else {
            return .noWindow
        }

        // Check hosting view's children
        var hostChildren: CFTypeRef?
        AXUIElementCopyAttributeValue(
            hostingView, kAXChildrenAttribute as CFString, &hostChildren
        )
        if let hostKids = hostChildren as? [AXUIElement], !hostKids.isEmpty {
            // Has children = showing the paused/disconnected UI
            return .paused
        }

        // No children = active mirroring (opaque video surface)
        return .connected
    }

    /// Press the Resume button when in paused state.
    func pressResume() -> Bool {
        guard let (window, _) = getMainWindow() else { return false }

        // Navigate: window > group (hosting view) > button
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement], let hostingView = kids.first else {
            return false
        }

        var hostChildren: CFTypeRef?
        AXUIElementCopyAttributeValue(
            hostingView, kAXChildrenAttribute as CFString, &hostChildren
        )
        guard let hostKids = hostChildren as? [AXUIElement] else { return false }

        for kid in hostKids {
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(kid, kAXRoleAttribute as CFString, &role)
            if let r = role as? String, r == kAXButtonRole as String {
                let pressResult = AXUIElementPerformAction(kid, kAXPressAction as CFString)
                return pressResult == .success
            }
        }
        return false
    }

    /// Maximum AX depth to search for the paused-overlay dismiss button.
    private static let maxOverlayButtonDepth = 8

    /// Button titles that dismiss a Continuity interruption overlay and free the
    /// session: the camera dialog's "OK" and the plain pause overlay's resume
    /// action (localized variants). Matched case-insensitively.
    private static let dismissButtonTitles: Set<String> = [
        "ok", "resume", "reprendre", "continuer", "réessayer", "reessayer",
    ]

    /// Screen-center of the overlay's *dismiss* button (e.g. the camera dialog's
    /// "OK"), located by title so we don't click a stray titlebar/toolbar control.
    /// See `MenuActionCapable.pausedDismissButtonPoint`.
    func pausedDismissButtonPoint() -> CGPoint? {
        guard let (window, _) = getMainWindow() else { return nil }
        guard let button = dismissButton(under: window, depth: 0),
              let geom = WindowListHelper.geometryFromAXElement(button) else { return nil }
        return CGPoint(
            x: geom.position.x + geom.size.width / 2,
            y: geom.position.y + geom.size.height / 2)
    }

    /// Depth-bounded search for an AXButton whose title/description is a known
    /// dismiss action. The active (connected) mirroring surface is opaque with no
    /// AX children, so a button is found only when an interruption overlay shows.
    private func dismissButton(under element: AXUIElement, depth: Int) -> AXUIElement? {
        if depth > Self.maxOverlayButtonDepth { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if let r = role as? String, r == kAXButtonRole as String,
           let title = buttonLabel(element),
           Self.dismissButtonTitles.contains(title) {
            return element
        }
        var children: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
        guard let kids = children as? [AXUIElement] else { return nil }
        for kid in kids {
            if let found = dismissButton(under: kid, depth: depth + 1) { return found }
        }
        return nil
    }

    /// Lower-cased title (or description) of a button element, or nil.
    private func buttonLabel(_ element: AXUIElement) -> String? {
        for attr in [kAXTitleAttribute, kAXDescriptionAttribute] {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, attr as CFString, &value)
            if let s = (value as? String)?.trimmingCharacters(in: .whitespaces).lowercased(),
               !s.isEmpty {
                return s
            }
        }
        return nil
    }

    /// Trigger a menu bar action (e.g., View > Home Screen).
    ///
    /// Uses an exact-string match on AX menu and item titles. On non-English
    /// macOS locales iPhone Mirroring's menu titles are translated and the
    /// AX lookup misses; for the three View-menu navigation items the
    /// Cmd+digit keyboard shortcuts are locale-invariant, so the bridge
    /// falls back to CGEvent in that case (issue #23).
    func triggerMenuAction(menu menuName: String, item itemName: String) -> Bool {
        if axTriggerMenuAction(menu: menuName, item: itemName) {
            return true
        }
        if let shortcut = MenuShortcuts.viewNavShortcut(for: itemName) {
            DebugLog.log("menu", "AX miss for '\(menuName)' > '\(itemName)' (likely localized title) — falling back to Cmd+\(shortcut.label)")
            return triggerKeyboardShortcut(keycode: shortcut.keycode)
        }
        return false
    }

    private func axTriggerMenuAction(menu menuName: String, item itemName: String) -> Bool {
        guard let app = findProcess() else { return false }
        let pid = app.processIdentifier
        let appRef = AXUIElementCreateApplication(pid)

        var menuBarValue: CFTypeRef?
        let menuBarResult = AXUIElementCopyAttributeValue(
            appRef, kAXMenuBarAttribute as CFString, &menuBarValue
        )
        guard menuBarResult == .success,
              let menuBarRef = menuBarValue,
              CFGetTypeID(menuBarRef) == AXUIElementGetTypeID()
        else { return false }
        let menuBar = unsafeDowncast(menuBarRef, to: AXUIElement.self)

        var menuBarChildren: CFTypeRef?
        AXUIElementCopyAttributeValue(
            menuBar, kAXChildrenAttribute as CFString, &menuBarChildren
        )
        guard let menuBarItems = menuBarChildren as? [AXUIElement] else { return false }

        for menuBarItem in menuBarItems {
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(menuBarItem, kAXTitleAttribute as CFString, &title)
            guard let t = title as? String, t == menuName else { continue }

            var submenuValue: CFTypeRef?
            AXUIElementCopyAttributeValue(
                menuBarItem, kAXChildrenAttribute as CFString, &submenuValue
            )
            guard let submenus = submenuValue as? [AXUIElement],
                  let submenu = submenus.first
            else { continue }

            var itemsValue: CFTypeRef?
            AXUIElementCopyAttributeValue(
                submenu, kAXChildrenAttribute as CFString, &itemsValue
            )
            guard let items = itemsValue as? [AXUIElement] else { continue }

            for item in items {
                var itemTitle: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &itemTitle)
                if let it = itemTitle as? String, it == itemName {
                    let result = AXUIElementPerformAction(item, kAXPressAction as CFString)
                    return result == .success
                }
            }
        }
        return false
    }

    /// Send a Cmd+<key> keyboard shortcut to iPhone Mirroring via CGEvent.
    /// Activates the app first so the event reaches the right window.
    private func triggerKeyboardShortcut(keycode: UInt16) -> Bool {
        guard let app = findProcess() else { return false }
        let alreadyFront = NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
        if !alreadyFront {
            app.activate()
            usleep(EnvConfig.spaceSwitchSettleUs)
        }
        return CGEventInput.postKey(keycode: keycode, flags: .maskCommand)
    }

    /// Determine device orientation from the mirroring window dimensions.
    /// When the iPhone rotates, the mirroring window resizes accordingly.
    func getOrientation() -> DeviceOrientation? {
        guard let info = getWindowInfo() else { return nil }
        return info.size.height > info.size.width ? .portrait : .landscape
    }

    /// Activate (bring to front) the iPhone Mirroring app and raise its window.
    /// Uses both NSRunningApplication.activate() and AXUIElement AXRaise to
    /// ensure the window becomes the key window that receives keyboard input.
    func activate() {
        findProcess()?.activate()
    }

    // MARK: - Private
}
