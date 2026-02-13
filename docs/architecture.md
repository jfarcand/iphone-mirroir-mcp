# Architecture

```
MCP Client (stdin/stdout JSON-RPC)
    │
    ▼
iphone-mirroir-mcp (user process)
    ├── PermissionPolicy   — fail-closed tool gating (config + CLI flags)
    ├── MirroringBridge    — AXUIElement window discovery + menu actions
    ├── ScreenCapture      — screencapture -l <windowID>
    ├── ScreenDescriber    — Vision OCR + coordinate grid overlay
    ├── InputSimulation    — activate-once + coordinate mapping
    │       ├── type_text  → activate if needed → HelperClient type
    │       ├── press_key  → activate if needed → HelperClient press_key
    │       └── tap/swipe  → HelperClient (Unix socket IPC)
    └── HelperClient       — Unix socket client
            │
            ▼  /var/run/iphone-mirroir-helper.sock
iphone-mirroir-helper (root LaunchDaemon)
    ├── CommandServer      — JSON command dispatch (click/type/press_key/swipe/move)
    └── KarabinerClient    — Karabiner DriverKit virtual HID protocol
            │
            ▼  /Library/Application Support/org.pqrs/tmp/rootonly/vhidd_server/*.sock
    Karabiner DriverKit Extension
            │
            ▼
    macOS HID System → iPhone Mirroring
```

## Input Paths

### Taps and Swipes

The helper warps the system cursor to the target coordinates, sends a Karabiner virtual pointing device button press, then restores the cursor. iPhone Mirroring's compositor layer requires input through the system HID path rather than programmatic CGEvent injection.

### Typing and Key Presses

The MCP server activates iPhone Mirroring via AppleScript System Events (the only reliable way to trigger a macOS Space switch), then sends HID keycodes through the helper's Karabiner virtual keyboard. Activation only happens when iPhone Mirroring isn't already frontmost, and the server does not restore the previous app — this eliminates the per-keystroke Space switching of earlier versions.

### Navigation

Home, Spotlight, and App Switcher use macOS Accessibility APIs to trigger iPhone Mirroring's menu bar actions directly (no window focus needed).
