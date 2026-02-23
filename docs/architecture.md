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
│  │ CGEvent posting │  │ Vision OCR pipeline      │    │
│  │ cursor mgmt     │  │ TapPointCalculator       │    │
│  │ layout xlate    │  │ GridOverlay              │    │
│  └────────┬────────┘  └──────────────────────────┘    │
│           │                                           │
│  ┌────────┴────────┐                                  │
│  │ CGEventInput    │                                  │
│  │ pointing + keys │                                  │
│  └────────┬────────┘                                  │
└───────────┼───────────────────────────────────────────┘
            │  CGEvent API
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

## Single Process

mirroir-mcp runs as a single user-level process. All input (pointing and keyboard) is delivered via the macOS CGEvent API — no helper daemon, no root privileges, no DriverKit extensions.

`HelperLib` is a shared Swift library linked into the main executable and all test targets. It contains key mappings, permission logic, timing config, and protocol types.

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
MCP Client → MCPServer → InputSimulation → CGEventInput
  → CGWarpMouseCursorPosition → CGEvent.post(tap: .cghidEventTap) → macOS HID → iPhone Mirroring
```

### Keyboard (type_text, press_key)

```
MCP Client → MCPServer → InputSimulation → ensureFrontmost() (AppleScript)
  → CGEventInput.postKey() → CGEvent.post(tap: .cghidEventTap) → macOS HID → iPhone Mirroring
```

### Navigation (press_home, press_app_switcher, spotlight)

```
MCP Client → MCPServer → MirroringBridge.triggerMenuAction() → AXUIElement Menu Bar → iPhone Mirroring
```

Direct Accessibility API call — no CGEvent involved.

### Observation (screenshot, describe_screen, status)

```
MCP Client → MCPServer → Bridge / Capture / Describer → AX API / screencapture / Vision OCR → Result
```

No input simulation involved.

## CursorSync Pattern

Every touch command follows this sequence:

```
1. Save      → CGEvent.location (current cursor position)
2. Disconnect → CGAssociateMouseAndMouseCursorPosition(false)
3. Warp      → CGWarpMouseCursorPosition(target)
4. Settle    → usleep(10ms)
5. Execute   → CGEvent click/drag/scroll via CGEventInput
6. Restore   → CGWarpMouseCursorPosition(savedPosition)
7. Reconnect → CGAssociateMouseAndMouseCursorPosition(true)
```

**Why disconnect?** Physical mouse movement during the sequence would interfere with target coordinates.

## Swipe vs Drag

| | Swipe | Drag |
|---|---|---|
| **macOS Input** | Scroll wheel events | Click-drag (button held) |
| **iOS Gesture** | Scroll / page swipe | Touch-and-drag (rearranging, sliders) |
| **Implementation** | `CGEvent` scroll wheel | `CGEvent` mouseDown + mouseDragged + mouseUp |

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
