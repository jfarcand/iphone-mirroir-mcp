// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Detects when the server binary has been rebuilt and self-reloads via execv().
// ABOUTME: Preserves PID and stdio file descriptors so the MCP client stays connected.

import Darwin
import Foundation

/// Checks the binary's mtime after each response and calls execv() to reload
/// when the binary on disk is newer than when the process started.
enum HotReload {

    /// Argument passed through execv so the restarted process skips the log reset.
    static let reloadFlag = "--hot-reload"

    /// Whether this process was started via hot-reload (vs. fresh launch).
    static let isReloaded: Bool = CommandLine.arguments.contains(reloadFlag)

    /// Mtime of the binary when the process started. Captured once on first access.
    private static let initialMtime: Date? = binaryMtime()

    /// Check if the binary on disk is newer than when we started, and replace
    /// the process image with the new binary via execv(). Called after each
    /// response is flushed so the client sees no interruption.
    static func reloadIfNeeded() {
        guard let initial = initialMtime,
              let current = binaryMtime(),
              current > initial else {
            return
        }

        DebugLog.persist("hot-reload", "Binary changed on disk, reloading via execv...")
        fflush(stderr)

        // Build argv: original args (minus any prior --hot-reload) plus the flag.
        var args = CommandLine.arguments.filter { $0 != reloadFlag }
        args.append(reloadFlag)
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cArgs.append(nil)
        execv(CommandLine.arguments[0], &cArgs)

        // execv only returns on failure
        DebugLog.persist("hot-reload", "execv failed: \(String(cString: strerror(errno)))")
    }

    /// Read the modification time of the running binary.
    private static func binaryMtime() -> Date? {
        let path = CommandLine.arguments[0]
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else {
            return nil
        }
        return mtime
    }
}
