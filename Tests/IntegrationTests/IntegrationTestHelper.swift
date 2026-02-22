// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
// ABOUTME: Shared setup logic for integration tests that target the FakeMirroring app.
// ABOUTME: Auto-detects FakeMirroring by process lookup and provides the bundle ID for bridge init.

import AppKit

/// Shared helpers for integration tests that need FakeMirroring.
enum IntegrationTestHelper {

    static let fakeBundleID = "com.jfarcand.FakeMirroring"

    /// Check if FakeMirroring is running by looking up its bundle ID in the process list.
    static var isFakeMirroringRunning: Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: fakeBundleID
        ).isEmpty
    }
}
