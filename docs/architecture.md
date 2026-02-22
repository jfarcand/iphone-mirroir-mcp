# Architecture

System architecture for mirroir-mcp.

## System Overview

```
MCP Client (Claude Code, Cursor, Copilot, etc.)
    │  stdin/stdout JSON-RPC 2.0
    ▼
┌───────────────────────────────────────────────────────┐
│  mirroir-mcp  (user process)                          │
│                                                       │
│  ┌─────────────────┐  ┌──────────────────────────┐    │
│  │ PermissionPolicy│  │ MCPServer                │    │
│  │ (fail-closed    │  │ JSON-RPC dispatch        │    │
│  │  tool gating)   │  │ protocol negotiation     │    │
│  └─────────────────┘  └──────────────────────────┘    │
│                                                       │
│  ┌─────────────────┐  ┌──────────────────────────┐    │
│  │ MirroringBridge │  │ ScreenCapture            │    │
│  │ AXUIElement     │──│ screencapture -l <winID> │    │
│  │ window discovery│  └──────────────────────────┘    │
│  │ menu actions    │  ┌──────────────────────────┐    │
│  │ state detection │  │ ScreenRecorder           │    │
│  └────────┬────────┘  │ screencapture -v         │    │
│           │           └──────────────────────────┘    │
│  ┌────────┴────────┐  ┌──────────────────────────┐    │
│  │ InputSimulation │  │ ScreenDescriber          │    │
│  │ coordinate map  │  │ Vision OCR pipeline      │    │
│  │ focus mgmt      │  │ TapPointCalculator       │    │
│  │ layout xlate    │  │ GridOverlay              │    │
│  └────────┬────────┘  └──────────────────────────┘    │
│           │                                           │
│  ┌────────┴────────┐                                  │
│  │ HelperClient    │                                  │
│  │ Unix socket IPC │                                  │
│  └────────┬────────┘                                  │
└───────────┼───────────────────────────────────────────┘
            │  /var/run/mirroir-helper.sock
            │  newline-delimited JSON
            ▼
┌───────────────────────────────────────────────────────┐
│  mirroir-helper  (root LaunchDaemon)                  │
│                                                       │
│  ┌─────────────────┐  ┌──────────────────────────┐    │
│  │ CommandServer   │  │ CommandHandlers          │    │
│  │ Unix stream     │──│ click, type, swipe,      │    │
│  │ socket listener │  │ drag, press_key, move,   │    │
│  └─────────────────┘  │ shake, long_press,       │    │
│                       │ double_tap, status        │    │
│                       └──────────┬───────────────┘    │
│  ┌─────────────────┐             │                    │
│  │ CursorSync      │◄────────────┘                    │
│  │ save/warp/nudge │                                  │
│  │ /restore cycle  │                                  │
│  └────────┬────────┘                                  │
│           │                                           │
│  ┌────────┴────────┐                                  │
│  │ KarabinerClient │                                  │
│  │ DriverKit vHID  │                                  │
│  │ wire protocol   │                                  │
│  └────────┬────────┘                                  │
└───────────┼───────────────────────────────────────────┘
            │  Unix DGRAM socket
            │  binary framed protocol
            ▼
┌───────────────────────────────────────────────────────┐
│  Karabiner DriverKit Extension (vhidd_server)         │
│  /Library/Application Support/org.pqrs/tmp/rootonly/  │
└───────────┬───────────────────────────────────────────┘
            │
            ▼
┌───────────────────────────────────────────────────────┐
│  macOS HID System                                     │
│       │                                               │
│       ▼                                               │
│  iPhone Mirroring.app  (Continuity compositor)        │
│       │                                               │
│       ▼                                               │
│  Physical iPhone (AirPlay + Bluetooth LE)             │
└───────────────────────────────────────────────────────┘
```

## Why Two Processes?

| Process | Runs As | Why |
|---------|---------|-----|
| `mirroir-mcp` | Current user | Window discovery, screenshots, OCR, app activation — all user-level APIs |
| `mirroir-helper` | root | Karabiner's virtual HID sockets live in a root-only directory; cursor warping requires CGEvent privileges |

`HelperLib` is a shared Swift library linked into both executables and all test targets. It contains key mappings, permission logic, timing config, packed binary structs, and protocol types.

## Tool Registration

`ToolHandlers.swift` delegates to category-specific registrars:

| Registrar | Tools |
|-----------|-------|
| `ScreenTools` | `screenshot`, `describe_screen`, `start_recording`, `stop_recording` |
| `InputTools` | `tap`, `swipe`, `drag`, `type_text`, `press_key`, `long_press`, `double_tap`, `shake` |
| `NavigationTools` | `launch_app`, `open_url`, `press_home`, `press_app_switcher`, `spotlight` |
| `InfoTools` | `status`, `get_orientation`, `check_health` |
| `SkillTools` | `list_skills`, `get_skill` |
| `CompilationTools` | `record_step`, `save_compiled` |
| `ScrollToTools` | `scroll_to` |
| `AppManagementTools` | `reset_app` |
| `MeasureTools` | `measure` |
| `NetworkTools` | `set_network` |

## Input Paths

### Touch (tap, long_press, double_tap)

```
MCP Client → MCPServer → InputSimulation → HelperClient
  → CommandServer → CursorSync → KarabinerClient → vhidd_server → macOS HID → iPhone Mirroring
```

### Keyboard (type_text, press_key)

```
MCP Client → MCPServer → InputSimulation → ensureFrontmost() (AppleScript)
  → HelperClient → CommandServer → KarabinerClient.typeKey() → vhidd_server → macOS HID → iPhone Mirroring
```

### Navigation (press_home, press_app_switcher, spotlight)

```
MCP Client → MCPServer → MirroringBridge.triggerMenuAction() → AXUIElement Menu Bar → iPhone Mirroring
```

No helper daemon involved — direct Accessibility API call.

### Observation (screenshot, describe_screen, status)

```
MCP Client → MCPServer → Bridge / Capture / Describer → AX API / screencapture / Vision OCR → Result
```

No helper daemon involved.

## CursorSync Pattern

Every touch command follows this sequence:

```
1. Save      → CGEvent.location (current cursor position)
2. Disconnect → CGAssociateMouseAndMouseCursorPosition(false)
3. Warp      → CGWarpMouseCursorPosition(target)
4. Settle    → usleep(10ms)
5. Nudge     → Karabiner pointing: +1 right, -1 left
6. Execute   → The actual input operation
7. Restore   → CGWarpMouseCursorPosition(savedPosition)
8. Reconnect → CGAssociateMouseAndMouseCursorPosition(true)
```

**Why nudge?** `CGWarpMouseCursorPosition` repositions the cursor but doesn't generate HID events. The nudge forces Karabiner's virtual pointing device to sync its internal position with the warped cursor.

**Why disconnect?** Physical mouse movement during the sequence would interfere with target coordinates.

## Swipe vs Drag

| | Swipe | Drag |
|---|---|---|
| **macOS Input** | Scroll wheel events | Click-drag (button held) |
| **iOS Gesture** | Scroll / page swipe | Touch-and-drag (rearranging, sliders) |
| **Implementation** | `PointingInput.verticalWheel` | `PointingInput.buttons = 0x01` + interpolated movement |

Getting them confused causes: swipe where drag intended → page scrolls instead of icon rearranging.

## Pluggable Targets

The target app is configured via environment variables:

| Variable | Default |
|----------|---------|
| `MIRROIR_BUNDLE_ID` | `com.apple.ScreenContinuity` |
| `MIRROIR_PROCESS_NAME` | `iPhone Mirroring` |

All subsystems flow through `MirroringBridge.findProcess()`, which reads these at the point of use. Changing the bundle ID switches the entire system to a different window.

`FakeMirroring` (`com.jfarcand.FakeMirroring`) is a minimal macOS app used in CI as a stand-in for iPhone Mirroring. See [Testing](testing.md).

## Protocol Abstractions

Five protocols enable dependency injection for testing:

| Protocol | Real Implementation |
|----------|-------------------|
| `MirroringBridging` | `MirroringBridge` |
| `InputProviding` | `InputSimulation` |
| `ScreenCapturing` | `ScreenCapture` |
| `ScreenRecording` | `ScreenRecorder` |
| `ScreenDescribing` | `ScreenDescriber` |

## Permission Engine

```
checkTool() → Readonly tool? → ALLOWED
           → skipPermissions? → ALLOWED
           → In deny list? → DENIED
           → In allow list (or wildcard '*')? → ALLOWED
           → Fail-closed → DENIED
```

**Readonly tools** (always allowed): `screenshot`, `describe_screen`, `start_recording`, `stop_recording`, `get_orientation`, `status`, `list_skills`, `get_skill`, `record_step`, `save_compiled`

Config: `.mirroir-mcp/permissions.json` (project-local) or `~/.mirroir-mcp/permissions.json` (global).

## JSON-RPC Protocol

JSON-RPC 2.0 over line-delimited stdin/stdout. Supports protocol versions `2025-11-25` (primary) and `2024-11-05` (fallback).

| Method | Description |
|--------|-------------|
| `initialize` | Protocol version negotiation |
| `tools/list` | Returns visible tools filtered by permission policy |
| `tools/call` | Permission check → tool handler dispatch |
| `ping` | Returns `{}` |

## Karabiner Wire Protocol

Communicates with Karabiner's DriverKit daemon via Unix datagram sockets.

| Struct | Size | Purpose |
|--------|------|---------|
| `KeyboardParameters` | 24 bytes | Device identity (vendorID=0x05ac, productID=0x0250) |
| `KeyboardInput` | 67 bytes | Modifier bitmask + 32 key slots (u16 HID keycodes) |
| `PointingInput` | 8 bytes | Buttons, x/y movement (i8), scroll wheels (i8) |

Heartbeats sent every 3s. Server socket monitored for daemon restarts.
