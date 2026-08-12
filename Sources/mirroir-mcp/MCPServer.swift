// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: MCP (Model Context Protocol) server implementing JSON-RPC 2.0 over stdio.
// ABOUTME: Handles initialize, tools/list, and tools/call methods per the MCP specification.

import Foundation
import HelperLib
import os

// MARK: - MCP Server

final class MCPServer: Sendable {
    private let tools = OSAllocatedUnfairLock(initialState: [String: MCPToolDefinition]())
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let policy: PermissionPolicy
    /// Counter for server-initiated request IDs (sampling, etc.).
    private let requestCounter = OSAllocatedUnfairLock(initialState: 0)
    init(policy: PermissionPolicy) {
        self.policy = policy
        encoder = JSONEncoder()
        decoder = JSONDecoder()
    }

    func registerTool(_ tool: MCPToolDefinition) {
        tools.withLock { $0[tool.name] = tool }
    }

    /// Run the MCP server, reading JSON-RPC from stdin and writing to stdout.
    func run() {
        // Use line-delimited JSON (one JSON object per line)
        while true {
            guard let line = readLine(strippingNewline: true) else { break }
            if line.isEmpty { continue }

            guard let data = line.data(using: .utf8) else {
                writeError(id: nil, code: -32700, message: "Parse error: invalid UTF-8")
                continue
            }

            let request: JSONRPCRequest
            do {
                request = try decoder.decode(JSONRPCRequest.self, from: data)
            } catch {
                DebugLog.log("MCPServer", "JSON-RPC decode failed: \(error)")
                writeError(id: nil, code: -32700, message: "Parse error: \(error.localizedDescription)")
                continue
            }

            guard let response = handleRequest(request) else {
                continue  // Notifications produce no response per JSON-RPC 2.0
            }
            writeResponse(response)
        }
    }

    /// Supported MCP protocol versions, most recent first. `2026-07-28` is the
    /// modern (stateless, per-request `_meta`) revision; the `2025-*`/`2024-*`
    /// entries are legacy (`initialize`-handshake) revisions. The server is
    /// dual-era: it serves both. See `handleRequest`.
    static let supportedProtocolVersions = ["2026-07-28", "2025-11-25", "2024-11-05"]

    /// Reserved `_meta` keys a modern (`2026-07-28`) client puts on every request.
    private enum MetaKey {
        static let protocolVersion = "io.modelcontextprotocol/protocolVersion"
        static let clientInfo = "io.modelcontextprotocol/clientInfo"
        static let clientCapabilities = "io.modelcontextprotocol/clientCapabilities"
    }

    /// How long a client may cache a `server/discover` response (1 hour).
    private static let discoverTtlMs = 3_600_000

    /// How long a client may cache a `tools/list` response (1 minute). Short by
    /// design: the visible tool set is derived from the permission policy on
    /// disk, so an edited `permissions.json` must take effect promptly.
    private static let toolsListTtlMs = 60_000

    func handleRequest(_ request: JSONRPCRequest) -> JSONRPCResponse? {
        // Notifications have no id — the spec says receivers MUST NOT respond
        if request.id == nil {
            return nil
        }

        // `server/discover` is the modern MUST-implement method and the stdio
        // backward-compat probe; it is answered regardless of negotiated era.
        if request.method == "server/discover" {
            return handleDiscover(request)
        }

        // Dual-era routing: a request carrying the modern `_meta`
        // protocolVersion is served statelessly per 2026-07-28; otherwise it is
        // a legacy request (post-`initialize`) and served as before. For modern
        // requests, validate the version and required `_meta` fields up front.
        let modernVersion = request.params?
            .member("_meta")?.member(MetaKey.protocolVersion)?.asString()
        let isModern = modernVersion != nil
        if let requested = modernVersion {
            if !Self.supportedProtocolVersions.contains(requested) {
                return unsupportedVersionError(id: request.id, requested: requested)
            }
            if let missing = missingRequiredMetaField(request) {
                return JSONRPCResponse(
                    id: request.id, result: nil,
                    error: JSONRPCError(
                        code: -32602,
                        message: "Invalid params: missing required _meta field '\(missing)'"
                    )
                )
            }
        }

        switch request.method {
        case "initialize":
            return handleInitialize(request)
        case "tools/list":
            return handleToolsList(request, modern: isModern)
        case "tools/call":
            return handleToolsCall(request, modern: isModern)
        case "ping":
            return JSONRPCResponse(id: request.id, result: completeResult([:], modern: isModern), error: nil)
        default:
            return JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    /// Wrap a modern result object with `resultType: "complete"`. Legacy
    /// (`initialize`-era) responses omit `resultType`; clients treat its
    /// absence as `"complete"` for backward compatibility.
    private func completeResult(_ fields: [String: JSONValue], modern: Bool) -> JSONValue {
        guard modern else { return .object(fields) }
        var withType = fields
        withType["resultType"] = .string("complete")
        return .object(withType)
    }

    /// Add the cache directives a modern (`2026-07-28`) list result must carry.
    /// The revision makes `ttlMs` and `cacheScope` required on `tools/list` and
    /// `server/discover` — a client validating against that schema rejects the
    /// whole result when either is absent.
    private func cacheable(
        _ fields: [String: JSONValue], ttlMs: Int, scope: CacheScope
    ) -> [String: JSONValue] {
        var withDirectives = fields
        withDirectives["ttlMs"] = .number(Double(ttlMs))
        withDirectives["cacheScope"] = .string(scope.rawValue)
        return withDirectives
    }

    /// Whether a cached result may be shared across users (`public`) or belongs
    /// to the client that fetched it (`private`).
    private enum CacheScope: String {
        case publicScope = "public"
        case privateScope = "private"
    }

    /// First required modern `_meta` field that is absent, or nil if all present.
    private func missingRequiredMetaField(_ request: JSONRPCRequest) -> String? {
        let meta = request.params?.member("_meta")
        if meta?.member(MetaKey.clientInfo) == nil { return MetaKey.clientInfo }
        if meta?.member(MetaKey.clientCapabilities) == nil { return MetaKey.clientCapabilities }
        return nil
    }

    /// `UnsupportedProtocolVersionError` (-32004) with the versions we support.
    private func unsupportedVersionError(id: RequestID?, requested: String) -> JSONRPCResponse {
        let supported = Self.supportedProtocolVersions.map { JSONValue.string($0) }
        let data: JSONValue = .object([
            "supported": .array(supported),
            "requested": .string(requested),
        ])
        return JSONRPCResponse(
            id: id, result: nil,
            error: JSONRPCError(code: -32004, message: "Unsupported protocol version", data: data)
        )
    }

    /// Modern `server/discover` — advertise supported versions, capabilities,
    /// and identity so a client can pick a version without a round-trip error.
    private func handleDiscover(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let supported = Self.supportedProtocolVersions.map { JSONValue.string($0) }
        var fields: [String: JSONValue] = [
            "resultType": .string("complete"),
            "supportedVersions": .array(supported),
            "capabilities": .object([
                "tools": .object([:]),
            ]),
            "serverInfo": .object([
                "name": .string("mirroir-mcp"),
                "version": .string(MirroirVersion.current),
            ]),
            "instructions": .string(
                "Drive a real iPhone via macOS iPhone Mirroring: see the screen "
                + "(describe_screen), tap/swipe/type, and author replayable skills."),
        ]
        // Identity and capabilities are the same for every client, so the
        // response is shareable.
        fields = cacheable(fields, ttlMs: Self.discoverTtlMs, scope: .publicScope)
        return JSONRPCResponse(id: request.id, result: .object(fields), error: nil)
    }

    /// Legacy (`initialize`-handshake) protocol versions, most recent first.
    /// `initialize` negotiates only among these — the modern `2026-07-28`
    /// revision has no handshake, so it is never the outcome of `initialize`.
    static let legacyProtocolVersions = ["2025-11-25", "2024-11-05"]

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        // Negotiate protocol version: use the client's version if it is a legacy
        // version we support, otherwise fall back to our most recent legacy one.
        let clientVersion = request.params?.getString("protocolVersion")
        let negotiatedVersion: String
        if let clientVersion, Self.legacyProtocolVersions.contains(clientVersion) {
            negotiatedVersion = clientVersion
        } else {
            negotiatedVersion = Self.legacyProtocolVersions[0]
        }

        let result: JSONValue = .object([
            "protocolVersion": .string(negotiatedVersion),
            "capabilities": .object([
                "tools": .object([:]),
                "sampling": .object([:]),
            ]),
            "serverInfo": .object([
                "name": .string("mirroir-mcp"),
                "version": .string(MirroirVersion.current),
            ]),
        ])
        return JSONRPCResponse(id: request.id, result: result, error: nil)
    }

    private func handleToolsList(_ request: JSONRPCRequest, modern: Bool) -> JSONRPCResponse {
        let toolList: [JSONValue] = tools.withLock { snapshot in
            snapshot.values
                .filter { policy.isToolVisible($0.name) }
                .map { tool in
                    .object([
                        "name": .string(tool.name),
                        "description": .string(tool.description),
                        "inputSchema": .object(tool.inputSchema),
                    ])
                }
        }
        var fields: [String: JSONValue] = ["tools": .array(toolList)]
        if modern {
            // The visible tool set is filtered by this machine's permission
            // policy, so the cached list belongs to the client that fetched it.
            fields = cacheable(fields, ttlMs: Self.toolsListTtlMs, scope: .privateScope)
        }
        let result = completeResult(fields, modern: modern)
        return JSONRPCResponse(id: request.id, result: result, error: nil)
    }

    private func handleToolsCall(_ request: JSONRPCRequest, modern: Bool) -> JSONRPCResponse {
        guard let toolName = request.params?.getToolName() else {
            return JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32602, message: "Missing tool name")
            )
        }

        guard let tool = tools.withLock({ $0[toolName] }) else {
            return JSONRPCResponse(
                id: request.id,
                result: nil,
                error: JSONRPCError(code: -32602, message: "Unknown tool: \(toolName)")
            )
        }

        let decision = policy.checkTool(toolName)
        DebugLog.log("permission", "checkTool(\(toolName))=\(decision)")
        if case .denied(let reason) = decision {
            let content: JSONValue = .array([
                MCPContent.text(reason).toJSON()
            ])
            let result = completeResult([
                "content": content,
                "isError": .bool(true),
            ], modern: modern)
            return JSONRPCResponse(id: request.id, result: result, error: nil)
        }

        let arguments = request.params?.getArguments() ?? [:]
        let toolResult = tool.handler(arguments)

        let content: JSONValue = .array(toolResult.content.map { $0.toJSON() })
        let result = completeResult([
            "content": content,
            "isError": .bool(toolResult.isError),
        ], modern: modern)
        return JSONRPCResponse(id: request.id, result: result, error: nil)
    }

    // MARK: - Server-to-Client Sampling

    /// Send a sampling/createMessage request to the MCP client and wait for the response.
    ///
    /// This is a server-initiated request: we write a JSON-RPC request to stdout and read
    /// the client's response from stdin. Safe to call from within a tool handler because
    /// the server's main loop is blocked waiting for the handler to return.
    ///
    /// - Parameter params: Sampling parameters (messages, max tokens, system prompt).
    /// - Returns: The sampling response text, or nil if the client doesn't support sampling.
    func sendSamplingRequest(_ params: SamplingParams) -> String? {
        let requestId = requestCounter.withLock { counter -> Int in
            counter += 1
            return counter
        }

        // Build JSON-RPC request for sampling/createMessage
        let request: [String: Any] = [
            "jsonrpc": "2.0",
            "id": requestId,
            "method": "sampling/createMessage",
            "params": encodeSamplingParams(params),
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: data, encoding: .utf8) else {
            DebugLog.log("sampling", "Failed to encode sampling request")
            return nil
        }

        // Send request to client
        print(jsonString)
        fflush(stdout)

        // Read response from client
        guard let responseLine = readLine(strippingNewline: true),
              let responseData = responseLine.data(using: .utf8) else {
            DebugLog.log("sampling", "No response from client for sampling request")
            return nil
        }

        // Parse JSON-RPC response
        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let content = result["content"] as? [String: Any],
              let text = content["text"] as? String else {
            DebugLog.log("sampling", "Failed to parse sampling response")
            return nil
        }

        return text
    }

    /// Encode SamplingParams to a dictionary for JSON serialization.
    private func encodeSamplingParams(_ params: SamplingParams) -> [String: Any] {
        var dict: [String: Any] = [
            "maxTokens": params.maxTokens,
        ]
        if let systemPrompt = params.systemPrompt {
            dict["systemPrompt"] = systemPrompt
        }

        dict["messages"] = params.messages.map { message -> [String: Any] in
            var msgDict: [String: Any] = ["role": message.role]
            switch message.content {
            case .text(let text):
                msgDict["content"] = ["type": "text", "text": text]
            case .mixed(let parts):
                msgDict["content"] = parts.map { part -> [String: Any] in
                    var partDict: [String: Any] = ["type": part.type]
                    if let text = part.text { partDict["text"] = text }
                    if let data = part.data { partDict["data"] = data }
                    if let mime = part.mimeType { partDict["mimeType"] = mime }
                    return partDict
                }
            }
            return msgDict
        }

        return dict
    }

    private func writeResponse(_ response: JSONRPCResponse) {
        let data: Data
        do {
            data = try encoder.encode(response)
        } catch {
            DebugLog.log("MCPServer", "Failed to encode response: \(error)")
            // Send a minimal error response as a fallback
            let fallback = #"{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"Internal error: response encoding failed"}}"#
            print(fallback)
            fflush(stdout)
            return
        }
        guard let jsonString = String(data: data, encoding: .utf8) else {
            DebugLog.log("MCPServer", "Response data is not valid UTF-8")
            return
        }
        print(jsonString)
        fflush(stdout)
    }

    private func writeError(id: RequestID?, code: Int, message: String) {
        let response = JSONRPCResponse(
            id: id,
            result: nil,
            error: JSONRPCError(code: code, message: message)
        )
        writeResponse(response)
    }
}
