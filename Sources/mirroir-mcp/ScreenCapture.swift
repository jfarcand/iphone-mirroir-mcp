// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Captures screenshots of the iPhone Mirroring window using screencapture CLI.
// ABOUTME: Returns base64-encoded PNG data suitable for MCP image responses.

import CoreGraphics
import Foundation
import HelperLib

/// Captures a target window as a screenshot using the macOS `screencapture` CLI.
/// Uses CGWindowListCreateImage is unavailable on macOS 15+ (replaced by
/// ScreenCaptureKit), so we shell out to `screencapture` instead.
///
/// Capture strategy:
/// 1. Try `screencapture -l <windowID>` (window-ID capture) — works for normal windows.
/// 2. If that fails (fullscreen / Split View windows), fall back to
///    `screencapture -R x,y,w,h` (region capture) using the window's known bounds.
final class ScreenCapture: Sendable {
    private let bridge: any WindowBridging

    init(bridge: any WindowBridging) {
        self.bridge = bridge
    }

    /// Capture the target window returning both screenshot data and window info.
    /// Single entry point — all other capture methods delegate here.
    func captureWithInfo() -> CaptureResult? {
        guard let info = bridge.getWindowInfo() else { return nil }

        // Activate the target so it's on the current Space — screencapture
        // cannot capture windows on other macOS Spaces.
        bridge.activate()
        usleep(EnvConfig.cursorSettleUs)

        let tempPath = NSTemporaryDirectory()
            + "mirroir-mcp-\(ProcessInfo.processInfo.processIdentifier).png"

        // Strategy 1: window-ID capture (requires valid CGWindowID)
        if info.windowID != 0, let data = captureByWindowID(info.windowID, to: tempPath) {
            return CaptureResult(data: data, info: info)
        }

        // Strategy 2: region capture (handles windowID=0, fullscreen, Split View)
        if info.windowID != 0 {
            DebugLog.log("ScreenCapture",
                "Window-ID capture failed for \(info.windowID), falling back to region capture")
        }
        guard let data = captureByRegion(info, to: tempPath) else { return nil }
        return CaptureResult(data: data, info: info)
    }

    /// Capture the target window and return raw PNG data.
    func captureData() -> Data? { captureWithInfo()?.data }

    /// Capture the target window and return base64-encoded PNG.
    func captureBase64() -> String? { captureData()?.base64EncodedString() }

    // Settled capture is a default capability of every ScreenCapturing
    // implementation — see the protocol extension at the bottom of this file.

    // MARK: - Capture strategies

    /// Capture a specific window by its CGWindowID using `screencapture -l`.
    private func captureByWindowID(_ windowID: CGWindowID, to path: String) -> Data? {
        return runScreencapture(
            arguments: ["-l", String(windowID), "-x", "-o", path],
            outputPath: path
        )
    }

    /// Capture a screen region matching the window bounds using `screencapture -R`.
    /// This works for fullscreen and Split View windows where -l fails.
    private func captureByRegion(_ info: WindowInfo, to path: String) -> Data? {
        let region = "\(Int(info.position.x)),\(Int(info.position.y)),"
            + "\(Int(info.size.width)),\(Int(info.size.height))"
        return runScreencapture(
            arguments: ["-R", region, "-x", "-o", path],
            outputPath: path
        )
    }

    /// Run screencapture with the given arguments and read the output file.
    private func runScreencapture(arguments: [String], outputPath: String) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = arguments

        do {
            try process.run()
        } catch {
            return nil
        }

        guard case .exited(let status) = process.waitWithTimeout(seconds: 10) else {
            process.terminate()
            return nil
        }

        guard status == 0 else { return nil }

        let fileURL = URL(fileURLWithPath: outputPath)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            return try Data(contentsOf: fileURL)
        } catch {
            DebugLog.log("ScreenCapture", "Failed to read screenshot: \(error)")
            return nil
        }
    }
}

/// Settled capture, available to every `ScreenCapturing` implementation.
///
/// Written against `captureWithInfo()` alone so it needs no cooperation from
/// conformers — real captures and test doubles settle by the same rules.
extension ScreenCapturing {

    /// Capture the target window once the screen has stopped changing.
    ///
    /// `screencapture` returns whatever the window server has already
    /// composited, and during mirroring that lags the device by at least a
    /// frame. A capture taken right after an action therefore shows the
    /// *pre-action* screen, so the action reads as a no-op even though it
    /// registered. Retrying on that false no-op is worse than slow: the first
    /// action did land, so the retry fires on the next screen and mis-taps.
    ///
    /// Capturing until two consecutive frames show identical pixels removes the
    /// ambiguity — a lagged frame differs from its successor, a settled one does
    /// not. A screen that never settles (spinner, video, blinking caret) returns
    /// its most recent frame once `timeoutUs` elapses: a live screen is still a
    /// truthful answer, and only a *stale* one is a lie.
    func captureSettledWithInfo(
        timeoutUs: UInt32 = EnvConfig.frameSettleTimeoutUs
    ) -> CaptureResult? {
        guard var previous = captureWithInfo() else { return nil }
        let deadline = DispatchTime.now().uptimeNanoseconds
            + (UInt64(timeoutUs) * UInt64(NSEC_PER_USEC))

        while DispatchTime.now().uptimeNanoseconds < deadline {
            usleep(EnvConfig.frameSettlePollUs)
            guard let current = captureWithInfo() else { return previous }
            if FrameFingerprint.sameContent(previous.data, current.data) {
                return current
            }
            previous = current
        }

        DebugLog.log("ScreenCapture", "frame did not settle within \(timeoutUs)us")
        return previous
    }

    /// Capture a settled frame and return base64-encoded PNG.
    func captureSettledBase64(timeoutUs: UInt32 = EnvConfig.frameSettleTimeoutUs) -> String? {
        captureSettledWithInfo(timeoutUs: timeoutUs)?.data.base64EncodedString()
    }
}
