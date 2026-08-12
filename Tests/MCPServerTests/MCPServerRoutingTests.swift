// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Tests for MCPServer JSON-RPC routing: initialize, tools/list, tools/call, ping, errors.
// ABOUTME: Verifies protocol version, capability negotiation, and error code compliance.

import XCTest
import HelperLib
@testable import mirroir_mcp

final class MCPServerRoutingTests: XCTestCase {

    private func makeServer(skipPermissions: Bool = true) -> MCPServer {
        let policy = PermissionPolicy(skipPermissions: skipPermissions, config: nil)
        return MCPServer(policy: policy)
    }

    private func makeRequest(method: String, id: RequestID? = .number(1), params: JSONValue? = nil) -> JSONRPCRequest {
        return JSONRPCRequest(jsonrpc: "2.0", id: id, method: method, params: params)
    }

    // MARK: - initialize

    func testInitializeReturnsProtocolVersionAndServerInfo() {
        let server = makeServer()
        let response = server.handleRequest(makeRequest(
            method: "initialize",
            params: .object(["protocolVersion": .string("2025-11-25")])
        ))

        guard let response else { return XCTFail("Expected response") }
        XCTAssertNil(response.error)
        guard case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }

        XCTAssertEqual(result["protocolVersion"], .string("2025-11-25"))

        guard case .object(let serverInfo) = result["serverInfo"] else {
            return XCTFail("Expected serverInfo object")
        }
        XCTAssertEqual(serverInfo["name"], .string("mirroir-mcp"))
        XCTAssertEqual(serverInfo["version"], .string(MirroirVersion.current))

        guard case .object(let capabilities) = result["capabilities"] else {
            return XCTFail("Expected capabilities object")
        }
        guard case .object(let tools) = capabilities["tools"] else {
            return XCTFail("Expected tools capability object")
        }
        XCTAssertTrue(tools.isEmpty)
    }

    func testInitializeNegotiatesClientVersion() {
        let server = makeServer()
        // Client requests 2024-11-05 — server supports it, should echo it back
        let response = server.handleRequest(makeRequest(
            method: "initialize",
            params: .object(["protocolVersion": .string("2024-11-05")])
        ))

        guard let response else { return XCTFail("Expected response") }
        guard case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertEqual(result["protocolVersion"], .string("2024-11-05"))
    }

    func testInitializeFallsBackToLatestForUnknownVersion() {
        let server = makeServer()
        // Client requests an unsupported version — server returns its latest
        let response = server.handleRequest(makeRequest(
            method: "initialize",
            params: .object(["protocolVersion": .string("9999-01-01")])
        ))

        guard let response else { return XCTFail("Expected response") }
        guard case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertEqual(result["protocolVersion"], .string("2025-11-25"))
    }

    func testInitializeWithNoParamsReturnsLatestVersion() {
        let server = makeServer()
        // No params at all — server returns its latest
        let response = server.handleRequest(makeRequest(method: "initialize"))

        guard let response else { return XCTFail("Expected response") }
        guard case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertEqual(result["protocolVersion"], .string("2025-11-25"))
    }

    // MARK: - tools/list

    func testToolsListWithNoToolsRegistered() {
        let server = makeServer()
        let response = server.handleRequest(makeRequest(method: "tools/list"))

        guard let response else { return XCTFail("Expected response") }
        XCTAssertNil(response.error)
        guard case .object(let result) = response.result,
              case .array(let tools) = result["tools"] else {
            return XCTFail("Expected tools array in result")
        }
        XCTAssertTrue(tools.isEmpty)
    }

    func testToolsListWithRegisteredTools() {
        let server = makeServer()
        server.registerTool(MCPToolDefinition(
            name: "test_tool",
            description: "A test tool",
            inputSchema: ["type": .string("object"), "properties": .object([:])],
            handler: { _ in .text("ok") }
        ))

        let response = server.handleRequest(makeRequest(method: "tools/list"))
        guard let response else { return XCTFail("Expected response") }
        guard case .object(let result) = response.result,
              case .array(let tools) = result["tools"] else {
            return XCTFail("Expected tools array")
        }
        XCTAssertEqual(tools.count, 1)

        guard case .object(let tool) = tools.first else {
            return XCTFail("Expected tool object")
        }
        XCTAssertEqual(tool["name"], .string("test_tool"))
        XCTAssertEqual(tool["description"], .string("A test tool"))
    }

    func testToolsListRespectsPermissionPolicy() {
        // Without skip-permissions, mutating tools are hidden
        let policy = PermissionPolicy(skipPermissions: false, config: nil)
        let server = MCPServer(policy: policy)

        server.registerTool(MCPToolDefinition(
            name: "tap",
            description: "Tap tool",
            inputSchema: ["type": .string("object")],
            handler: { _ in .text("ok") }
        ))
        server.registerTool(MCPToolDefinition(
            name: "screenshot",
            description: "Screenshot tool",
            inputSchema: ["type": .string("object")],
            handler: { _ in .text("ok") }
        ))

        let response = server.handleRequest(makeRequest(method: "tools/list"))
        guard let response else { return XCTFail("Expected response") }
        guard case .object(let result) = response.result,
              case .array(let tools) = result["tools"] else {
            return XCTFail("Expected tools array")
        }

        // Only screenshot should be visible (readonly); tap is mutating and not permitted
        let toolNames = tools.compactMap { value -> String? in
            guard case .object(let obj) = value else { return nil }
            return obj["name"]?.asString()
        }
        XCTAssertTrue(toolNames.contains("screenshot"))
        XCTAssertFalse(toolNames.contains("tap"))
    }

    // MARK: - tools/call

    func testToolsCallMissingToolName() {
        let server = makeServer()
        let response = server.handleRequest(makeRequest(
            method: "tools/call",
            params: .object([:])
        ))

        guard let response else { return XCTFail("Expected response") }
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32602)
        XCTAssertEqual(response.error?.message, "Missing tool name")
    }

    func testToolsCallUnknownTool() {
        let server = makeServer()
        let response = server.handleRequest(makeRequest(
            method: "tools/call",
            params: .object(["name": .string("nonexistent")])
        ))

        guard let response else { return XCTFail("Expected response") }
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32602)
        XCTAssertTrue(response.error?.message.contains("Unknown tool") ?? false)
    }

    func testToolsCallDeniedTool() {
        let policy = PermissionPolicy(skipPermissions: false, config: nil)
        let server = MCPServer(policy: policy)

        server.registerTool(MCPToolDefinition(
            name: "tap",
            description: "Tap",
            inputSchema: ["type": .string("object")],
            handler: { _ in .text("tapped") }
        ))

        let response = server.handleRequest(makeRequest(
            method: "tools/call",
            params: .object(["name": .string("tap")])
        ))

        guard let response else { return XCTFail("Expected response") }
        // Denied tools return a result with isError=true, not a JSON-RPC error
        XCTAssertNil(response.error)
        guard case .object(let result) = response.result else {
            return XCTFail("Expected result object")
        }
        XCTAssertEqual(result["isError"], .bool(true))
    }

    func testToolsCallValidTool() {
        let server = makeServer()
        server.registerTool(MCPToolDefinition(
            name: "test_tool",
            description: "Test",
            inputSchema: ["type": .string("object")],
            handler: { args in
                let name = args["name"]?.asString() ?? "world"
                return .text("hello \(name)")
            }
        ))

        let response = server.handleRequest(makeRequest(
            method: "tools/call",
            params: .object([
                "name": .string("test_tool"),
                "arguments": .object(["name": .string("test")]),
            ])
        ))

        guard let response else { return XCTFail("Expected response") }
        XCTAssertNil(response.error)
        guard case .object(let result) = response.result,
              case .array(let content) = result["content"],
              case .object(let textObj) = content.first else {
            return XCTFail("Expected content array with text object")
        }
        XCTAssertEqual(textObj["text"], .string("hello test"))
        XCTAssertEqual(result["isError"], .bool(false))
    }

    // MARK: - ping

    func testPingReturnsEmptyResult() {
        let server = makeServer()
        let response = server.handleRequest(makeRequest(method: "ping"))

        guard let response else { return XCTFail("Expected response") }
        XCTAssertNil(response.error)
        guard case .object(let result) = response.result else {
            return XCTFail("Expected empty object")
        }
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Unknown method

    func testUnknownMethodReturnsError() {
        let server = makeServer()
        let response = server.handleRequest(makeRequest(method: "bogus/method"))

        guard let response else { return XCTFail("Expected response") }
        XCTAssertNotNil(response.error)
        XCTAssertEqual(response.error?.code, -32601)
        XCTAssertTrue(response.error?.message.contains("Method not found") ?? false)
    }

    // MARK: - Notifications (no id → no response)

    func testNotificationWithNoIdReturnsNil() {
        let server = makeServer()
        // Notifications have no id — spec says MUST NOT respond
        let response = server.handleRequest(makeRequest(
            method: "notifications/initialized",
            id: nil
        ))
        XCTAssertNil(response, "Notifications must not produce a response")
    }

    func testAnyNotificationWithNoIdReturnsNil() {
        let server = makeServer()
        // Any method sent without an id is a notification
        let response = server.handleRequest(makeRequest(
            method: "notifications/cancelled",
            id: nil
        ))
        XCTAssertNil(response, "All notifications (no id) must not produce a response")
    }

    // MARK: - Modern protocol (2026-07-28): server/discover + per-request _meta

    /// Build a modern request whose `_meta` carries the required reverse-DNS
    /// protocol fields for the given version.
    private func modernRequest(
        method: String, version: String = "2026-07-28",
        includeClientInfo: Bool = true, includeClientCapabilities: Bool = true,
        extraParams: [String: JSONValue] = [:]
    ) -> JSONRPCRequest {
        var meta: [String: JSONValue] = [
            "io.modelcontextprotocol/protocolVersion": .string(version),
        ]
        if includeClientInfo {
            meta["io.modelcontextprotocol/clientInfo"] =
                .object(["name": .string("test-client"), "version": .string("1.0")])
        }
        if includeClientCapabilities {
            meta["io.modelcontextprotocol/clientCapabilities"] = .object([:])
        }
        var params = extraParams
        params["_meta"] = .object(meta)
        return makeRequest(method: method, params: .object(params))
    }

    func testServerDiscoverReturnsSupportedVersionsAndCapabilities() {
        let server = makeServer()
        let response = server.handleRequest(makeRequest(method: "server/discover"))
        guard let response else { return XCTFail("Expected response") }
        XCTAssertNil(response.error)
        guard case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertEqual(result["resultType"], .string("complete"))
        guard case .array(let versions) = result["supportedVersions"] else {
            return XCTFail("Expected supportedVersions array")
        }
        XCTAssertTrue(versions.contains(.string("2026-07-28")), "must advertise the modern version")
        XCTAssertTrue(versions.contains(.string("2025-11-25")), "must still advertise legacy")
        guard case .object(let caps) = result["capabilities"],
              case .object = caps["tools"] else {
            return XCTFail("Expected tools capability")
        }
        // Identity lives in result `_meta`, the revision's canonical location
        // for it — `DiscoverResult` itself has no serverInfo field.
        guard case .object(let meta) = result["_meta"],
              case .object(let info)? = meta["io.modelcontextprotocol/serverInfo"] else {
            return XCTFail("Expected _meta serverInfo")
        }
        XCTAssertEqual(info["name"], .string("mirroir-mcp"))
        XCTAssertNotNil(info["version"], "Implementation requires name and version")
        XCTAssertNil(result["serverInfo"], "identity belongs in _meta, not top level")
        // Cacheable per the spec: both directives are required, not optional.
        XCTAssertNotNil(result["ttlMs"])
        XCTAssertEqual(result["cacheScope"], .string("public"))
    }

    func testModernToolsListIncludesResultType() {
        let server = makeServer()
        let response = server.handleRequest(modernRequest(method: "tools/list"))
        guard let response, case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertNil(response.error)
        XCTAssertEqual(result["resultType"], .string("complete"),
            "modern result responses must carry resultType")
        XCTAssertNotNil(result["tools"])
    }

    /// The revision says servers should report their identity on every modern
    /// result, in `_meta` under the reserved reverse-DNS key.
    func testModernResultsCarryServerInfoMeta() {
        let server = makeServer()
        for method in ["tools/list", "ping"] {
            guard let response = server.handleRequest(modernRequest(method: method)),
                  case .object(let result) = response.result,
                  case .object(let meta)? = result["_meta"],
                  case .object(let info)? = meta["io.modelcontextprotocol/serverInfo"] else {
                return XCTFail("\(method): expected _meta serverInfo")
            }
            XCTAssertEqual(info["name"], .string("mirroir-mcp"), "\(method): server name")
            XCTAssertNotNil(info["version"], "\(method): server version")
        }
    }

    func testLegacyResultsOmitServerInfoMeta() {
        let server = makeServer()
        // Legacy clients learn the identity from the initialize handshake.
        guard let response = server.handleRequest(makeRequest(method: "tools/list")),
              case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertNil(result["_meta"], "legacy results carry no modern _meta envelope")
    }

    /// `2026-07-28` makes `ttlMs`/`cacheScope` required on `tools/list`; a client
    /// validating against that schema rejects the entire result if either is
    /// missing, so tool discovery fails outright.
    func testModernToolsListCarriesCacheDirectives() {
        let server = makeServer()
        let response = server.handleRequest(modernRequest(method: "tools/list"))
        guard let response, case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        guard case .number(let ttl)? = result["ttlMs"] else {
            return XCTFail("modern tools/list must carry ttlMs")
        }
        XCTAssertGreaterThanOrEqual(ttl, 0, "ttlMs must be a non-negative integer")
        XCTAssertEqual(ttl, ttl.rounded(), "ttlMs must be an integer")
        XCTAssertEqual(result["cacheScope"], .string("private"),
            "the tool set is filtered per-machine by the permission policy")
    }

    func testLegacyToolsListOmitsResultType() {
        let server = makeServer()
        // No modern _meta → legacy request → no resultType (clients treat absence as complete).
        let response = server.handleRequest(makeRequest(method: "tools/list"))
        guard let response, case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertNil(result["resultType"], "legacy responses must not include resultType")
        XCTAssertNil(result["ttlMs"], "cache directives are a modern-revision field")
        XCTAssertNil(result["cacheScope"], "cache directives are a modern-revision field")
    }

    func testModernUnsupportedVersionReturnsError() {
        let server = makeServer()
        let response = server.handleRequest(modernRequest(method: "tools/list", version: "1900-01-01"))
        guard let response, let error = response.error else {
            return XCTFail("Expected error")
        }
        // -32022 is the spec-allocated code; the -32000..-32019 range is
        // implementation-defined and carries no cross-implementation meaning.
        XCTAssertEqual(error.code, -32022, "unsupported version → UnsupportedProtocolVersionError")
        guard case .object(let data)? = error.data,
              case .array(let supported) = data["supported"] else {
            return XCTFail("Expected data.supported list")
        }
        XCTAssertTrue(supported.contains(.string("2026-07-28")))
        XCTAssertEqual(data["requested"], .string("1900-01-01"))
    }

    func testModernMissingRequiredMetaFieldReturnsInvalidParams() {
        let server = makeServer()
        // protocolVersion present but clientCapabilities missing → malformed
        // modern request; the revision requires that field.
        let response = server.handleRequest(
            modernRequest(method: "tools/list", includeClientCapabilities: false))
        guard let response, let error = response.error else {
            return XCTFail("Expected error")
        }
        XCTAssertEqual(error.code, -32602, "missing required _meta field → Invalid params")
    }

    /// `clientInfo` is optional in the revision's request envelope — rejecting a
    /// request that omits it would turn away conformant clients.
    func testModernRequestWithoutClientInfoIsAccepted() {
        let server = makeServer()
        let response = server.handleRequest(
            modernRequest(method: "tools/list", includeClientInfo: false))
        guard let response, case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertNil(response.error, "clientInfo is optional, not required")
        XCTAssertNotNil(result["tools"])
    }

    func testInitializeNeverNegotiatesModernVersion() {
        let server = makeServer()
        // A legacy initialize must not yield the handshake-less modern version,
        // even if the client names it.
        let response = server.handleRequest(makeRequest(
            method: "initialize",
            params: .object(["protocolVersion": .string("2026-07-28")])
        ))
        guard let response, case .object(let result) = response.result else {
            return XCTFail("Expected object result")
        }
        XCTAssertEqual(result["protocolVersion"], .string("2025-11-25"),
            "initialize negotiates only legacy versions")
    }
}
