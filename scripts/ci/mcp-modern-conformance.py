#!/usr/bin/env python3
# ABOUTME: Validates mirroir-mcp's modern (2026-07-28) MCP results against the official schema.
# ABOUTME: Drives the revision's handshake over stdio and checks each result with jsonschema.

"""Modern-revision MCP conformance check.

The `2026-07-28` revision is stateless: there is no `initialize` handshake, and
every request carries a `_meta` envelope naming the protocol version. Results
must satisfy the published schema — notably `resultType` on every result and the
`ttlMs`/`cacheScope` cache directives on every cacheable one. A client that
validates against the schema discards a whole result when a required field is
missing, which surfaces as "connected, but no tools".

The schema lives alongside this script (`mcp-schema-2026-07-28.json`), copied
verbatim from the modelcontextprotocol specification repository, so the check
neither hits the network nor restates the contract in hand-written assertions.

Usage: mcp-modern-conformance.py <path-to-mirroir-mcp-binary>
"""

import json
import subprocess
import sys
from pathlib import Path

try:
    from jsonschema import Draft202012Validator
except ImportError:
    sys.exit(
        "jsonschema is required for MCP conformance validation.\n"
        "Install it with: pip3 install jsonschema"
    )

SCHEMA_PATH = Path(__file__).with_name("mcp-schema-2026-07-28.json")
PROTOCOL_VERSION = "2026-07-28"

# Each modern request paired with the schema definition its result must satisfy.
# The last case omits the optional `clientInfo`: the revision requires only
# `protocolVersion` and `clientCapabilities`, so a server that demands more
# rejects conformant clients.
CASES = [
    ("server/discover", {}, "DiscoverResult", True),
    ("tools/list", {}, "ListToolsResult", True),
    ("tools/call", {"name": "list_skills", "arguments": {}}, "CallToolResult", True),
    ("ping", {}, "EmptyResult", True),
    ("tools/list", {}, "ListToolsResult", False),
]


def envelope(with_client_info):
    """The `_meta` every modern request carries."""
    meta = {
        "io.modelcontextprotocol/protocolVersion": PROTOCOL_VERSION,
        "io.modelcontextprotocol/clientCapabilities": {},
    }
    if with_client_info:
        meta["io.modelcontextprotocol/clientInfo"] = {
            "name": "mirroir-conformance", "version": "1.0"
        }
    return meta


def run_requests(binary):
    """Send every case to the server over stdio and return results keyed by id."""
    lines = []
    for index, (method, params, _, with_client_info) in enumerate(CASES):
        payload = dict(params)
        payload["_meta"] = envelope(with_client_info)
        lines.append(json.dumps(
            {"jsonrpc": "2.0", "id": index, "method": method, "params": payload}
        ))

    completed = subprocess.run(
        [binary],
        input="\n".join(lines) + "\n",
        capture_output=True,
        text=True,
        timeout=120,
        check=False,
    )

    responses = {}
    for line in completed.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "id" in message:
            responses[message["id"]] = message
    return responses


def validate(schema, responses):
    """Check every case's result against its schema definition.

    Returns a list of human-readable failures; empty means conformant.
    """
    failures = []
    for index, (method, _, definition, with_client_info) in enumerate(CASES):
        label = method if with_client_info else f"{method} (no clientInfo)"
        message = responses.get(index)
        if message is None:
            failures.append(f"{label}: no response")
            continue
        if "error" in message and message["error"] is not None:
            failures.append(f"{label}: server returned error {message['error']}")
            continue

        subschema = {"$ref": f"#/$defs/{definition}", "$defs": schema["$defs"]}
        errors = sorted(
            Draft202012Validator(subschema).iter_errors(message["result"]),
            key=lambda e: list(e.path),
        )
        for error in errors:
            location = "/".join(str(part) for part in error.path) or "<root>"
            failures.append(f"{label} ({definition}) at {location}: {error.message}")
    return failures


def main():
    if len(sys.argv) != 2:
        sys.exit(f"usage: {Path(sys.argv[0]).name} <path-to-mirroir-mcp-binary>")

    binary = sys.argv[1]
    schema = json.loads(SCHEMA_PATH.read_text())
    responses = run_requests(binary)
    failures = validate(schema, responses)

    if failures:
        print(f"MCP {PROTOCOL_VERSION} conformance FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1

    print(f"OK ({len(CASES)} modern results conform to {PROTOCOL_VERSION})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
