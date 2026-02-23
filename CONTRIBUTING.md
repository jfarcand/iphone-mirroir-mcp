# Contributing to iPhone Mirroir MCP

Thank you for your interest in contributing! By submitting a contribution, you agree to the [Contributor License Agreement](CLA.md). Your Git commit metadata (name and email) serves as your electronic signature.

## Getting Started

1. Fork the repository and clone your fork
2. Run the [installer](mirroir.sh) to build the server binary
3. Read this guide to understand the system
4. Create a feature branch for your work

## Project Structure

```
mirroir-mcp/
├── Sources/
│   ├── mirroir-mcp/     # MCP server + CLI subcommands (user process)
│   │   ├── mirroir_mcp.swift  # Entry point (dispatches test/record subcommands)
│   │   ├── MCPServer.swift           # JSON-RPC 2.0 dispatch
│   │   ├── ToolHandlers.swift        # Tool registration orchestrator
│   │   ├── ScreenTools.swift         # screenshot, describe_screen, recording
│   │   ├── InputTools.swift          # tap, swipe, drag, type, press_key, etc.
│   │   ├── NavigationTools.swift     # launch_app, open_url, home, spotlight
│   │   ├── ScrollToTools.swift       # scroll_to — scroll until element visible
│   │   ├── AppManagementTools.swift  # reset_app — force-quit via App Switcher
│   │   ├── MeasureTools.swift        # measure — time screen transitions
│   │   ├── NetworkTools.swift        # set_network — toggle airplane/wifi/cellular
│   │   ├── InfoTools.swift           # status, get_orientation, check_health
│   │   ├── SkillTools.swift          # list_skills, get_skill (SKILL.md + YAML)
│   │   ├── SkillMdParser.swift      # SKILL.md front matter parser
│   │   ├── MigrateCommand.swift     # mirroir migrate — YAML → SKILL.md conversion
│   │   ├── Protocols.swift           # DI protocol abstractions
│   │   ├── MirroringBridge.swift     # AX window discovery + menu actions
│   │   ├── InputSimulation.swift     # Coordinate mapping + focus management
│   │   ├── CGEventInput.swift        # CGEvent posting for pointing + keyboard
│   │   ├── CGKeyMap.swift            # Character → macOS virtual keycode mapping
│   │   ├── ScreenCapture.swift       # screencapture -l wrapper
│   │   ├── ScreenRecorder.swift      # Video recording state machine
│   │   ├── ScreenDescriber.swift     # Vision OCR pipeline
│   │   ├── DebugLog.swift            # Debug logging to stderr + file
│   │   ├── TestRunner.swift          # `mirroir test` orchestrator
│   │   ├── SkillParser.swift         # YAML → structured SkillStep list (used by test runner)
│   │   ├── StepExecutor.swift        # Runs steps against real subsystems
│   │   ├── ElementMatcher.swift      # Fuzzy OCR text matching (exact/case/substring)
│   │   ├── ConsoleReporter.swift     # Terminal output formatting for test runner
│   │   ├── JUnitReporter.swift       # JUnit XML generation for CI
│   │   ├── EventRecorder.swift       # `mirroir record` — CGEvent tap monitoring
│   │   ├── YAMLGenerator.swift       # Recorded events → skill YAML
│   │   └── RecordCommand.swift       # `mirroir record` CLI entry point
│   │
│   └── HelperLib/              # Shared library (linked into main executable + tests)
│       ├── MCPProtocol.swift         # JSON-RPC + MCP types (JSONValue, tool defs)
│       ├── PermissionPolicy.swift    # Fail-closed permission engine
│       ├── KeyName.swift             # Named key normalization
│       ├── AppleScriptKeyMap.swift   # macOS virtual key codes
│       ├── LayoutMapper.swift        # Non-US keyboard layout translation
│       ├── TimingConstants.swift     # Default timing values
│       ├── EnvConfig.swift           # Environment variable overrides
│       ├── TapPointCalculator.swift  # Smart OCR tap coordinate offset
│       ├── GridOverlay.swift         # Coordinate grid overlay on screenshots
│       ├── ContentBoundsDetector.swift # Detects iPhone content bounds in screenshots
│       └── ProcessExtensions.swift   # Timeout-aware Process.wait
│
├── Tests/
│   ├── MCPServerTests/         # XCTest — server routing + tool handlers
│   ├── HelperLibTests/         # Swift Testing — shared library utilities
│   ├── TestRunnerTests/        # Swift Testing — test runner, recorder, skill parser
│   ├── IntegrationTests/       # XCTest — FakeMirroring integration (requires running app)
│   └── Fixtures/               # Test skill files (YAML + SKILL.md)
│
├── scripts/                    # Install/uninstall scripts
└── docs/                       # Documentation
```

## Build & Test

### Commands

| Task | Command |
|------|---------|
| Build | `swift build` |
| Build release | `swift build -c release` |
| Run all tests | `swift test` |
| Run specific test | `swift test --filter <TestClassName>/<testMethodName>` |
| Clean | `swift package clean` |
| Resolve dependencies | `swift package resolve` |

### Tiered Validation

**Tier 1 — Quick Iteration** (during development):
```bash
swift build
swift test --filter <TestClassName>/<testMethodName>
```

**Tier 2 — Pre-Commit** (before committing):
```bash
swift build
swift test
```

**Tier 3 — Full Validation** (before merge):
```bash
swift build -c release
swift test
```

### Pre-commit Hooks

The project uses Git hooks (`.githooks/pre-commit`) that enforce:

1. **Apache 2.0 license headers** on all Swift files (except `Package.swift`)
2. **ABOUTME headers** — every non-test Swift file must have a 2-line ABOUTME comment
3. **No suspicious files** — blocks `.bak`, `.orig`, `.tmp`, `.swp` files
4. **Swift build** — compilation must succeed
5. **MCP compliance** — validates protocol version, server name, and tool schema (when MCP files change)

Set up the hooks:
```bash
git config core.hooksPath .githooks
```

## How to Add a New MCP Tool

Follow these steps to add a new tool. This example adds a hypothetical `pinch_zoom` tool.

### Step 1: Classify the Tool

Decide if the tool is **readonly** (observation) or **mutating** (changes iPhone state).

In `Sources/HelperLib/PermissionPolicy.swift`, add the tool name to the appropriate set:

```swift
// Mutating — requires explicit permission
public static let mutatingTools: Set<String> = [
    // ... existing tools ...
    "pinch_zoom",
]
```

### Step 2: Add Protocol Method

If the tool needs a protocol abstraction (most input tools do), add a method to the relevant protocol in `Sources/mirroir-mcp/Protocols.swift`:

```swift
protocol InputProviding: Sendable {
    // ... existing methods ...
    func pinchZoom(x: Double, y: Double, scale: Double) -> String?
}
```

### Step 3: Implement the Method

Add the implementation to `InputSimulation`:

```swift
func pinchZoom(x: Double, y: Double, scale: Double) -> String? {
    // Coordinate mapping, CGEvent posting, etc.
}
```

### Step 4: Register the Tool

Add the `MCPToolDefinition` in the appropriate category file (e.g., `InputTools.swift`):

```swift
server.registerTool(MCPToolDefinition(
    name: "pinch_zoom",
    description: "Pinch to zoom at a specific point",
    inputSchema: [
        "type": .string("object"),
        "properties": .object([
            "x": .object(["type": .string("number"), "description": .string("X coordinate")]),
            "y": .object(["type": .string("number"), "description": .string("Y coordinate")]),
            "scale": .object(["type": .string("number"), "description": .string("Zoom scale factor")]),
        ]),
        "required": .array([.string("x"), .string("y"), .string("scale")]),
    ],
    handler: { args in
        // Extract args, call input.pinchZoom(), return MCPToolResult
    }
))
```

### Step 5: Update Test Doubles

Add stub methods in:

- `Tests/MCPServerTests/TestDoubles.swift` — add to `StubInput`

### Step 6: Write Tests

Add tests in `Tests/MCPServerTests/` for tool handler logic and `Tests/HelperLibTests/` for shared utilities.

### Step 7: Update Documentation

- Add the tool to `docs/tools.md`

## Test Architecture

### Test Targets

| Target | Framework | Tests | Purpose |
|--------|-----------|-------|---------|
| `MCPServerTests` | XCTest | Server routing, tool handler logic | Verifies JSON-RPC dispatch, tool parameter validation, permission enforcement |
| `HelperLibTests` | Swift Testing | Shared utilities | Verifies key mapping, permissions, protocol types, OCR coordinates, layout translation |
| `TestRunnerTests` | Swift Testing | Test runner, recorder, skill parser | Verifies skill parsing, step execution, element matching, event classification, reporters |

### Dependency Injection

All test targets use protocol-based DI. Real implementations are swapped with stubs:

**MCPServerTests stubs** (`TestDoubles.swift`):
- `StubBridge` — configurable window info, state, orientation
- `StubInput` — configurable results for tap/swipe/type/etc.
- `StubCapture` — returns configured base64 screenshot data
- `StubRecorder` — returns configured recording start/stop results
- `StubDescriber` — returns configured OCR describe results

## Environment Variable Overrides

All timing and numeric constants can be overridden via environment variables. The variable name follows the pattern `MIRROIR_<CONSTANT_NAME>`.

### Cursor & Input Settling

| Variable | Default | Description |
|----------|---------|-------------|
| `MIRROIR_CURSOR_SETTLE_US` | 10,000 (10ms) | Wait after cursor warp for macOS to register position |
| `MIRROIR_CLICK_HOLD_US` | 80,000 (80ms) | Button hold duration for single tap |
| `MIRROIR_DOUBLE_TAP_HOLD_US` | 40,000 (40ms) | Button hold per tap in double-tap |
| `MIRROIR_DOUBLE_TAP_GAP_US` | 50,000 (50ms) | Gap between taps in double-tap |
| `MIRROIR_DRAG_MODE_HOLD_US` | 150,000 (150ms) | Hold before drag movement for iOS drag recognition |
| `MIRROIR_FOCUS_SETTLE_US` | 200,000 (200ms) | Wait after keyboard focus click |
| `MIRROIR_KEYSTROKE_DELAY_US` | 15,000 (15ms) | Delay between keystrokes |
| `MIRROIR_DEAD_KEY_DELAY_US` | 30,000 (30ms) | Delay in dead-key compose sequences (accented characters) |

### App Switching & Navigation

| Variable | Default | Description |
|----------|---------|-------------|
| `MIRROIR_SPACE_SWITCH_SETTLE_US` | 300,000 (300ms) | Wait after macOS Space switch |
| `MIRROIR_SPOTLIGHT_APPEARANCE_US` | 800,000 (800ms) | Wait for Spotlight to appear |
| `MIRROIR_SEARCH_RESULTS_POPULATE_US` | 1,000,000 (1.0s) | Wait for search results |
| `MIRROIR_SAFARI_LOAD_US` | 1,500,000 (1.5s) | Wait for Safari page load |
| `MIRROIR_ADDRESS_BAR_ACTIVATE_US` | 500,000 (500ms) | Wait for address bar activation |
| `MIRROIR_PRE_RETURN_US` | 300,000 (300ms) | Wait before pressing Return |

### Process & System Polling

| Variable | Default | Description |
|----------|---------|-------------|
| `MIRROIR_PROCESS_POLL_US` | 50,000 (50ms) | Polling interval for process completion |
| `MIRROIR_EARLY_FAILURE_DETECT_US` | 500,000 (500ms) | Wait before checking for early process failure |
| `MIRROIR_RESUME_FROM_PAUSED_US` | 2,000,000 (2.0s) | Wait after resuming paused mirroring |

### Non-Timing Constants

| Variable | Default | Description |
|----------|---------|-------------|
| `MIRROIR_DRAG_INTERPOLATION_STEPS` | 60 | Number of movement steps in drag |
| `MIRROIR_SWIPE_INTERPOLATION_STEPS` | 20 | Number of scroll steps in swipe |
| `MIRROIR_SCROLL_PIXEL_SCALE` | 8.0 | Divisor converting pixels to scroll ticks |

### App Identity

| Variable | Default | Description |
|----------|---------|-------------|
| `MIRROIR_BUNDLE_ID` | `com.apple.ScreenContinuity` | Target app bundle ID for process discovery |
| `MIRROIR_PROCESS_NAME` | `iPhone Mirroring` | Target app display name for messages |

### Keyboard Layout

| Variable | Default | Description |
|----------|---------|-------------|
| `IPHONE_KEYBOARD_LAYOUT` | *(not set)* | Opt-in non-US keyboard layout for character translation (e.g., `Canadian-CSA` or `com.apple.keylayout.Canadian-CSA`). When unset, US QWERTY keycodes are sent. |

## Code Conventions

### File Headers

Every Swift file must have:
1. Apache 2.0 license header (enforced by pre-commit hook)
2. Two-line ABOUTME comment explaining the file's purpose:

```swift
// Copyright 2026 jfarcand@apache.org
// Licensed under the Apache License, Version 2.0
//
// ABOUTME: Brief description of what this file does.
// ABOUTME: Second line with additional context.
```

### Error Handling

- Use `throws` / `try` / `catch` for error propagation
- Use `Result<T, Error>` for async or callback-based error handling
- Custom error types must conform to `Error` protocol
- No `try!` except for static data known valid at compile time
- No `fatalError()` except in unreachable code paths

### Concurrency

- All shared types must conform to `Sendable`
- Use `OSAllocatedUnfairLock` for protecting mutable state
- Protocol abstractions enable safe dependency injection

### Logging

- All logging goes to **stderr** (stdout is reserved for JSON-RPC)
- Use `DebugLog.log()` for debug-only messages
- Use `DebugLog.persist()` for messages that always appear in the log file
- Never log access tokens, API keys, passwords, or secrets

### Git Workflow

- **Features:** Create a branch (`feature/my-feature`), squash merge locally to main
- **Bug fixes:** Commit directly to main
- **Never create Pull Requests** — all merges happen locally
- Commit messages: 1-2 lines, no AI assistant references
