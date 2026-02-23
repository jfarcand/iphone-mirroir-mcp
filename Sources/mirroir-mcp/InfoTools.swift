// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Registers info-related MCP tools: get_orientation, status.
// ABOUTME: Each tool maps MCP JSON-RPC calls to the bridge for querying mirroring state.

import Foundation
import HelperLib

extension MirroirMCP {
    static func registerInfoTools(
        server: MCPServer,
        registry: TargetRegistry
    ) {
        // get_orientation — report device orientation
        server.registerTool(MCPToolDefinition(
            name: "get_orientation",
            description: """
                Get the current device orientation of the mirrored iPhone. \
                Returns "portrait" or "landscape" based on the mirroring \
                window dimensions. Useful for adapting touch coordinates \
                and understanding the current screen layout.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([:]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                let bridge = ctx.bridge

                guard let orientation = bridge.getOrientation() else {
                    return .error(
                        "Cannot determine orientation. Is target '\(ctx.name)' running?")
                }

                let info = bridge.getWindowInfo()
                let sizeDesc = info.map {
                    "\(Int($0.size.width))x\(Int($0.size.height))"
                } ?? "unknown"

                return .text(
                    "Orientation: \(orientation.rawValue) (window: \(sizeDesc))")
            }
        ))

        // check_health — single diagnostic tool for setup debugging
        server.registerTool(MCPToolDefinition(
            name: "check_health",
            description: """
                Run a comprehensive health check of the iPhone Mirroring setup. \
                Checks mirroring window state, screen capture availability, \
                and accessibility permissions. \
                Use this to diagnose setup issues in a single call.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([:]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                let bridge = ctx.bridge
                let capture = ctx.capture

                var checks: [String] = []
                var allOk = true

                // 1. Target process
                let process = bridge.findProcess()
                if process != nil {
                    checks.append("[ok] '\(ctx.name)' process is running")
                } else {
                    checks.append("[FAIL] '\(ctx.name)' process is not running")
                    allOk = false
                }

                // 2. Window state
                let state = bridge.getState()
                switch state {
                case .connected:
                    let info = bridge.getWindowInfo()
                    let size = info.map {
                        "\(Int($0.size.width))x\(Int($0.size.height))"
                    } ?? "unknown"
                    checks.append("[ok] '\(ctx.name)' connected (window: \(size))")
                case .paused:
                    checks.append("[WARN] '\(ctx.name)' is paused — click the window to resume")
                    allOk = false
                case .noWindow:
                    checks.append("[FAIL] '\(ctx.name)' running but no window found")
                    allOk = false
                case .notRunning:
                    checks.append("[FAIL] '\(ctx.name)' not running")
                    allOk = false
                }

                // 3. Screen capture
                let screenshot = capture.captureBase64()
                if screenshot != nil {
                    checks.append("[ok] Screen capture working")
                } else {
                    checks.append(
                        "[FAIL] Screen capture failed — " +
                        "grant Screen Recording permission in System Settings")
                    allOk = false
                }

                let summary = allOk ? "All checks passed" : "Issues detected"
                let output = "\(summary)\n\n" + checks.joined(separator: "\n")
                return .text(output)
            }
        ))

        // status — get the current mirroring connection state
        server.registerTool(MCPToolDefinition(
            name: "status",
            description: """
                Get the current status of the iPhone Mirroring connection. \
                Returns whether the app is running, connected, paused, or has no window.
                """,
            inputSchema: [
                "type": .string("object"),
                "properties": .object([:]),
            ],
            handler: { args in
                let (ctx, err) = registry.resolveForTool(args)
                guard let ctx else { return err! }
                let bridge = ctx.bridge

                let state = bridge.getState()
                let mirroringStatus: String
                switch state {
                case .connected:
                    let info = bridge.getWindowInfo()
                    let sizeDesc =
                        info.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "unknown"
                    let posDesc =
                        info.map { "pos=(\(Int($0.position.x)),\(Int($0.position.y)))" } ?? "pos=unknown"
                    let orientDesc = bridge.getOrientation()?.rawValue ?? "unknown"
                    mirroringStatus = "Connected — mirroring active (window: \(sizeDesc), \(posDesc), \(orientDesc))"
                case .paused:
                    mirroringStatus = "Paused — connection paused, can resume"
                case .notRunning:
                    mirroringStatus = "Not running — '\(ctx.name)' is not open"
                case .noWindow:
                    mirroringStatus = "No window — app is running but no mirroring window found"
                }

                return .text(mirroringStatus)
            }
        ))
    }
}
