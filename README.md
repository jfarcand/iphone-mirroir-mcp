# iphone-mirroir-mcp

MCP server that drives a real iPhone through macOS iPhone Mirroring. Screenshot, tap, swipe, type, navigate — any MCP client, any agent.

No simulator. No jailbreak. No app on the phone. Your actual device.

## Security

**This gives an AI agent full control of your iPhone screen.** It can tap anything, type anything, open any app — autonomously. That includes banking apps, messages, and payments. Understand what you're connecting before you install.

The MCP server only works while iPhone Mirroring is active. Closing the window or locking the phone kills all input. The helper daemon listens on a local Unix socket only (no network). The helper runs as root (Karabiner's HID sockets require it) — source is ~500 lines, audit it yourself.

## Requirements

- macOS 14+
- iPhone Mirroring connected
- Xcode Command Line Tools (`xcode-select --install`)
- **Screen Recording** + **Accessibility** permissions for your terminal
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) (optional, recommended — without it, taps may not register on the DRM surface)

## Quick Start

```bash
# Build
swift build -c release

# Install the Karabiner helper (requires sudo — prompts for password)
./scripts/install-helper.sh

# Add to your MCP client config (.mcp.json)
```

```json
{
  "mcpServers": {
    "iphone-mirroring": {
      "command": "/absolute/path/to/.build/release/iphone-mirroir-mcp"
    }
  }
}
```

### Karabiner Setup

If you don't have Karabiner-Elements installed:

```bash
brew install --cask karabiner-elements    # requires admin password
```

Open Karabiner-Elements Settings, approve the DriverKit extension when macOS prompts, then verify:

```bash
ls /Library/Application\ Support/org.pqrs/tmp/rootonly/vhidd_server/*.sock
```

### Verify Helper

```bash
sudo launchctl list | grep iphone-mirroir
cat /var/log/iphone-mirroir-helper.log
```

### Uninstall

```bash
./scripts/uninstall-helper.sh    # requires sudo
```

## Tools

| Tool | Parameters | Description |
|------|-----------|-------------|
| `screenshot` | — | Capture iPhone screen as base64 PNG. Auto-resumes paused sessions. |
| `tap` | `x`, `y` | Tap at coordinates relative to the mirroring window content area. |
| `swipe` | `from_x`, `from_y`, `to_x`, `to_y`, `duration_ms`? | Swipe between two points. Default 300ms. |
| `type_text` | `text` | Type into the focused text field. US QWERTY layout. |
| `press_home` | — | Go to home screen (View > Home Screen menu action). |
| `press_app_switcher` | — | Open the app switcher. |
| `spotlight` | — | Open Spotlight search. |
| `status` | — | Mirroring state + helper/device readiness. |

## How It Works

iPhone Mirroring streams the phone screen to a macOS window. The screen is a DRM-protected video surface — no accessibility tree, no DOM. The agent uses vision (screenshots) to decide where to tap.

- **Screenshots**: `screencapture -l <CGWindowID>`
- **Input**: Karabiner DriverKit virtual HID (bypasses DRM), CGEvent fallback
- **Navigation**: macOS accessibility APIs on the mirroring app's menu bar

```
stdin (JSON-RPC) -> MCPServer         Unix Socket        iphone-mirroir-helper
                        |           <------------>        (LaunchDaemon, root)
           +------------+------------+                          |
           v            v            v                    KarabinerClient
    MirroringBridge  ScreenCapture  InputSimulation             |
    (AXUIElement)   (screencapture) (HelperClient)        Karabiner DriverKit
                                    (CGEvent fb)          Virtual HID Device
```

## License

Apache 2.0
