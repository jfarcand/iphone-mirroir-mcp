// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
// ABOUTME: Fake macOS app that mimics the iPhone Mirroring window for integration testing.
// ABOUTME: Renders a settings-like screen with header, rows, and tab bar for OCR and icon detection.

import AppKit

/// View that renders an iOS Settings-style screen for OCR testing.
/// Draws a large title, category rows, and a tab bar with icons.
final class FakeScreenView: NSView {

    /// Status bar time display.
    private let statusBarLabel = ("9:41", CGPoint(x: 175, y: 30))

    /// Large title in the header zone.
    private let headerLabel = ("Settings", CGPoint(x: 100, y: 120))

    /// Category rows — simulate tappable list items like iOS Settings.
    private let rowLabels: [(String, CGPoint)] = [
        ("General", CGPoint(x: 100, y: 250)),
        ("Display", CGPoint(x: 100, y: 310)),
        ("Privacy", CGPoint(x: 100, y: 370)),
        ("About", CGPoint(x: 100, y: 430)),
        ("Software Update", CGPoint(x: 130, y: 490)),
        ("Developer", CGPoint(x: 110, y: 550)),
    ]

    /// Disclosure indicators for rows (simulating ">" chevrons).
    private let chevronX: CGFloat = 370

    override var isFlipped: Bool { true }

    /// Tab bar icon positions (x-center) and sizes — 5 evenly spaced icons
    /// on a white bar at the bottom, simulating an iOS tab bar for icon detection testing.
    private let tabBarHeight: CGFloat = 60
    private let iconSize: CGFloat = 24
    private let tabBarIconXPositions: [CGFloat] = [50, 130, 210, 290, 370]

    /// Tab bar labels below each icon — simulates real iOS tab bars with text labels
    /// positioned in the bottom zone of the window for tap offset testing.
    private let tabBarLabels = ["Home", "Search", "Feed", "Chat", "Profile"]

    /// Row height and separator styling.
    private let rowHeight: CGFloat = 44
    private let separatorInset: CGFloat = 20

    override func draw(_ dirtyRect: NSRect) {
        // Dark background for high OCR contrast
        NSColor(red: 0.1, green: 0.1, blue: 0.15, alpha: 1.0).setFill()
        dirtyRect.fill()

        drawStatusBar()
        drawHeader()
        drawRows()
        drawTabBar()
    }

    private func drawStatusBar() {
        let font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let (text, origin) = statusBarLabel
        let size = (text as NSString).size(withAttributes: attrs)
        let centeredX = origin.x - size.width / 2
        (text as NSString).draw(at: NSPoint(x: centeredX, y: origin.y), withAttributes: attrs)
    }

    private func drawHeader() {
        let font = NSFont.systemFont(ofSize: 28, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let (text, origin) = headerLabel
        (text as NSString).draw(at: NSPoint(x: origin.x, y: origin.y), withAttributes: attrs)
    }

    private func drawRows() {
        let rowFont = NSFont.systemFont(ofSize: 18, weight: .regular)
        let rowAttrs: [NSAttributedString.Key: Any] = [
            .font: rowFont,
            .foregroundColor: NSColor.white,
        ]
        let chevronFont = NSFont.systemFont(ofSize: 18, weight: .regular)
        let chevronAttrs: [NSAttributedString.Key: Any] = [
            .font: chevronFont,
            .foregroundColor: NSColor(white: 0.5, alpha: 1.0),
        ]

        for (text, origin) in rowLabels {
            // Draw row text
            (text as NSString).draw(at: NSPoint(x: origin.x, y: origin.y), withAttributes: rowAttrs)

            // Draw chevron indicator
            (">" as NSString).draw(
                at: NSPoint(x: chevronX, y: origin.y), withAttributes: chevronAttrs)

            // Draw separator line below row
            let separatorY = origin.y + rowHeight
            NSColor(white: 0.3, alpha: 1.0).setStroke()
            let path = NSBezierPath()
            path.move(to: NSPoint(x: separatorInset, y: separatorY))
            path.line(to: NSPoint(x: bounds.width - separatorInset, y: separatorY))
            path.lineWidth = 0.5
            path.stroke()
        }
    }

    private func drawTabBar() {
        // Draw white tab bar background at the bottom
        let barY = bounds.height - tabBarHeight
        NSColor.white.setFill()
        NSRect(x: 0, y: barY, width: bounds.width, height: tabBarHeight).fill()

        // Draw dark icon shapes (simple filled rectangles) on the tab bar
        let iconColor = NSColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0)
        iconColor.setFill()
        let iconY = barY + 6
        for iconX in tabBarIconXPositions {
            let rect = NSRect(
                x: iconX - iconSize / 2,
                y: iconY,
                width: iconSize,
                height: iconSize
            )
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        }

        // Draw text labels below each icon
        let labelFont = NSFont.systemFont(ofSize: 10, weight: .medium)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: iconColor,
        ]
        let labelY = iconY + iconSize + 4
        for (idx, label) in tabBarLabels.enumerated() {
            let size = (label as NSString).size(withAttributes: labelAttrs)
            let x = tabBarIconXPositions[idx] - size.width / 2
            (label as NSString).draw(at: NSPoint(x: x, y: labelY), withAttributes: labelAttrs)
        }
    }
}

/// Application delegate that creates the main window.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let windowWidth: CGFloat = 410
        let windowHeight: CGFloat = 898

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FakeMirroring"
        window.contentView = FakeScreenView(frame: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight))
        window.makeKeyAndOrderFront(nil)
        self.window = window

        buildMenuBar()
    }

    /// Build a View menu with navigation items for AX menu traversal tests.
    private func buildMenuBar() {
        let mainMenu = NSMenu()

        // App menu (required by macOS)
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "Quit FakeMirroring", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // View menu with navigation items
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(NSMenuItem(title: "Home Screen", action: #selector(noOp(_:)), keyEquivalent: ""))
        viewMenu.addItem(NSMenuItem(title: "Spotlight", action: #selector(noOp(_:)), keyEquivalent: ""))
        viewMenu.addItem(NSMenuItem(title: "App Switcher", action: #selector(noOp(_:)), keyEquivalent: ""))
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func noOp(_ sender: Any?) {
        // Menu items exist for AX traversal testing; no action needed.
    }
}

// Launch the app
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
