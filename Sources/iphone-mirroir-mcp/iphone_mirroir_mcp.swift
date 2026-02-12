// Copyright 2026 jfarcand
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Entry point for the iPhone Mirroring MCP server.
// ABOUTME: Initializes subsystems and starts the JSON-RPC server loop over stdio.

import Darwin
import Foundation
import HelperLib

@main
struct IPhoneMirroirMCP {
    static func main() {
        // Ignore SIGPIPE so the server doesn't crash when the MCP client
        // disconnects or its stdio pipe closes unexpectedly.
        signal(SIGPIPE, SIG_IGN)

        // Redirect stderr for logging (stdout is reserved for MCP JSON-RPC)
        let bridge = MirroringBridge()
        let capture = ScreenCapture(bridge: bridge)
        let recorder = ScreenRecorder(bridge: bridge)
        let input = InputSimulation(bridge: bridge)
        let describer = ScreenDescriber(bridge: bridge)
        let server = MCPServer()

        registerTools(server: server, bridge: bridge, capture: capture,
                      recorder: recorder, input: input, describer: describer)

        // Start the MCP server loop
        server.run()
    }
}

// MARK: - JSONValue convenience extensions

extension JSONValue {
    func asString() -> String? {
        if case .string(let s) = self { return s }
        return nil
    }

    func asNumber() -> Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    func asInt() -> Int? {
        if case .number(let n) = self { return Int(n) }
        return nil
    }

    func asStringArray() -> [String]? {
        guard case .array(let items) = self else { return nil }
        return items.compactMap { $0.asString() }
    }
}
