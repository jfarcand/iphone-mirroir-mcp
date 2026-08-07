// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Live process lookup for window bridges, independent of the main run loop.
// ABOUTME: Replaces NSWorkspace's snapshot, which freezes in the stdio MCP server.

import AppKit

/// Locates running applications from live system state.
///
/// `NSWorkspace.shared.runningApplications` is only updated when the main run
/// loop runs in a common mode. The MCP server spends its entire lifetime
/// blocked in `readLine()`, so that snapshot freezes at whatever the process
/// last observed. When the target app relaunches — an iPhone respring restarts
/// ScreenContinuity — the frozen snapshot keeps the terminated instance and its
/// dead PID, and reports `isTerminated == false` for it because that property is
/// refreshed by the same run loop. Every AX call against the dead PID then fails
/// with `kAXErrorCannotComplete`, which a bridge reports as `.noWindow` for the
/// rest of the server's lifetime; nothing short of restarting the server clears
/// it, and quitting the target app does not help.
///
/// Launch Services answers from live state, so these lookups stay correct across
/// target restarts without any run loop trip.
enum RunningAppLocator {

    /// The running application with `bundleID`, or nil when none is running.
    static func byBundleID(_ bundleID: String) -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { !$0.isTerminated }
    }

    /// The running application whose localized name is `name`, or nil.
    ///
    /// Launch Services offers no lookup by name, so apps without a bundle
    /// identifier (QEMU-based emulators) are matched against the NSWorkspace
    /// snapshot and then re-resolved by PID: `NSRunningApplication(processIdentifier:)`
    /// reads live state and returns nil for a process that has exited, so a
    /// frozen snapshot can no longer hand back a dead PID. The name is checked
    /// again on the re-resolved instance in case the PID was recycled.
    /// Discovering a process that launched *after* the snapshot froze is left to
    /// the caller's CGWindowList scan (`GenericWindowBridge.findWindowInList`),
    /// which is itself live.
    static func byLocalizedName(_ name: String) -> NSRunningApplication? {
        guard let candidate = NSWorkspace.shared.runningApplications.first(
            where: { $0.localizedName == name })
        else { return nil }
        let live = NSRunningApplication(processIdentifier: candidate.processIdentifier)
        return live?.localizedName == name ? live : nil
    }
}
