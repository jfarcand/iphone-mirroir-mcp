# mirroir-mcp

MCP server that controls a real iPhone through macOS iPhone Mirroring. Screenshot, tap, swipe, type — from any MCP client.

This npm package downloads the pre-built macOS binary from [GitHub releases](https://github.com/jfarcand/mirroir-mcp/releases).

## Requirements

- macOS 15+ with iPhone Mirroring
- iPhone connected via iPhone Mirroring

## Install

```bash
npm install -g mirroir-mcp
```

Then add to your MCP client config:

```json
{
  "mcpServers": {
    "mirroir": {
      "command": "mirroir-mcp"
    }
  }
}
```

See the [full documentation](https://github.com/jfarcand/mirroir-mcp) for details.

## License

Apache-2.0
