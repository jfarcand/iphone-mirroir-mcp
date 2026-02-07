# iphone-mirroir-mcp

MCP server that controls a real iPhone through macOS iPhone Mirroring. Screenshot, tap, swipe, type — from any MCP client.

No simulator. No jailbreak. No app on the phone. Your actual device.

## What Works

- **Screenshots** — captures the mirrored iPhone screen as PNG
- **Taps** — click anywhere on the iPhone screen
- **Swipes** — drag between two points
- **Typing** — type text into any focused text field (US QWERTY)
- **Navigation** — Home, App Switcher, Spotlight via menu bar actions

All input goes through a Karabiner DriverKit virtual HID device, which bypasses iPhone Mirroring's DRM-protected surface. Without Karabiner, taps and typing won't register.

## Security Warning

**This gives an AI agent full control of your iPhone screen.** It can tap anything, type anything, open any app — autonomously. That includes banking apps, messages, and payments.

The MCP server only works while iPhone Mirroring is active. Closing the window or locking the phone kills all input. The helper daemon listens on a local Unix socket only (no network). The helper runs as root (Karabiner's HID sockets require it) — the full source is ~2500 lines of Swift, audit it yourself.

## Requirements

- macOS 15+ with iPhone Mirroring
- iPhone connected via iPhone Mirroring
- Xcode Command Line Tools (`xcode-select --install`)
- **Screen Recording** + **Accessibility** permissions for your terminal
- [Karabiner-Elements](https://karabiner-elements.pqrs.org/) installed and activated

## Install

### Prerequisites

1. [Karabiner-Elements](https://karabiner-elements.pqrs.org/) installed and activated:

```bash
brew install --cask karabiner-elements
```

Open Karabiner-Elements, approve the DriverKit system extension when macOS prompts.

2. Xcode Command Line Tools:

```bash
xcode-select --install
```

### Option A: Homebrew

```bash
brew tap jfarcand/tap
brew install iphone-mirroir-mcp
sudo brew services start iphone-mirroir-mcp
```

Follow the caveats printed after install (`brew info iphone-mirroir-mcp`).

### Option B: From source

```bash
git clone https://github.com/jfarcand/iphone-mirroir-mcp.git
cd iphone-mirroir-mcp
./install.sh
```

The installer builds both binaries, configures the Karabiner ignore rule, and installs the helper daemon. It prompts for sudo once.

### Add to your MCP client

Add to your `.mcp.json` (Claude Code, Cursor, etc.):

```json
{
  "mcpServers": {
    "iphone-mirroring": {
      "command": "/path/to/iphone-mirroir-mcp"
    }
  }
}
```

For Homebrew: use the path printed by `brew info iphone-mirroir-mcp`.
For source: use `.build/release/iphone-mirroir-mcp` in the cloned directory.

### Grant permissions

Open iPhone Mirroring, then run a `screenshot` tool call. macOS will prompt for:
- **Screen Recording** — needed for `screencapture`
- **Accessibility** — needed for window discovery and menu bar actions

Grant both to your terminal app.

## Tools

| Tool | Parameters | Description |
|------|-----------|-------------|
| `screenshot` | — | Capture the iPhone screen as base64 PNG |
| `tap` | `x`, `y` | Tap at coordinates (relative to mirroring window) |
| `swipe` | `from_x`, `from_y`, `to_x`, `to_y`, `duration_ms`? | Swipe between two points (default 300ms) |
| `type_text` | `text` | Type into the focused text field (US QWERTY) |
| `press_home` | — | Go to home screen |
| `press_app_switcher` | — | Open app switcher |
| `spotlight` | — | Open Spotlight search |
| `status` | — | Connection state and device readiness |

Coordinates are in points relative to the mirroring window's top-left corner. Screenshots are Retina 2x — divide pixel coordinates by 2 to get tap coordinates.

## Architecture

```
MCP Client (stdin/stdout JSON-RPC)
    │
    ▼
iphone-mirroir-mcp (user process)
    ├── MirroringBridge    — AXUIElement window discovery + menu actions
    ├── ScreenCapture      — screencapture -l <windowID>
    ├── InputSimulation    — coordinate mapping, focus management
    └── HelperClient       — Unix socket client
            │
            ▼  /var/run/iphone-mirroir-helper.sock
iphone-mirroir-helper (root LaunchDaemon)
    ├── CommandServer      — JSON command dispatch
    └── KarabinerClient    — Karabiner DriverKit virtual HID protocol
            │
            ▼  /Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/*.sock
    Karabiner DriverKit Extension
            │
            ▼
    macOS HID System → iPhone Mirroring
```

The helper runs as root because Karabiner's virtual HID sockets are in a root-only directory. It creates a virtual keyboard and a virtual pointing device through Karabiner's DriverKit extension. Clicks warp the system cursor to the target, send a Karabiner pointing report, then restore the cursor. Typing clicks the iPhone Mirroring title bar first to ensure keyboard focus, then sends HID keyboard reports.

## Updating

After pulling new code:

```bash
# Rebuild and reinstall helper
sudo ./scripts/reinstall-helper.sh

# Reconnect the MCP server in your client
```

## Uninstall

```bash
./scripts/uninstall-helper.sh
```

Removes the helper binary, LaunchDaemon plist, socket, and log file.

## Troubleshooting

**`keyboard_ready: false`** — Karabiner's DriverKit extension isn't running. Open Karabiner-Elements Settings and make sure the extension is approved.

**Typing goes to terminal instead of iPhone** — The Karabiner ignore rule is missing. Add the `devices` entry from step 2 to your `karabiner.json`.

**Taps don't register** — Check that the helper is running (`echo '{"action":"status"}' | nc -U /var/run/iphone-mirroir-helper.sock`). If not, reinstall with `sudo ./scripts/reinstall-helper.sh`.

**"Mirroring paused" screenshots** — The MCP server auto-resumes paused sessions. If it persists, click the iPhone Mirroring window manually once.

**Helper won't start after reinstall** — Run `sudo launchctl bootout system/com.jfarcand.iphone-mirroir-helper` first, then `sudo ./scripts/reinstall-helper.sh`.

## License

Apache 2.0
