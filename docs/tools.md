# Tools Reference

All 18 tools exposed by the MCP server. Mutating tools require [permission](permissions.md) to appear in `tools/list`.

## Tool List

| Tool | Parameters | Description |
|------|-----------|-------------|
| `screenshot` | — | Capture the iPhone screen as base64 PNG |
| `describe_screen` | — | OCR the screen and return text elements with tap coordinates plus a grid-overlaid screenshot |
| `start_recording` | `output_path`? | Start video recording of the mirrored screen |
| `stop_recording` | — | Stop recording and return the .mov file path |
| `tap` | `x`, `y` | Tap at coordinates (relative to mirroring window) |
| `double_tap` | `x`, `y` | Two rapid taps for zoom/text selection |
| `long_press` | `x`, `y`, `duration_ms`? | Hold tap for context menus (default 500ms) |
| `swipe` | `from_x`, `from_y`, `to_x`, `to_y`, `duration_ms`? | Swipe between two points (default 300ms) |
| `drag` | `from_x`, `from_y`, `to_x`, `to_y`, `duration_ms`? | Slow sustained drag for icons, sliders (default 1000ms) |
| `type_text` | `text` | Type text — activates iPhone Mirroring and sends keystrokes |
| `press_key` | `key`, `modifiers`? | Send a special key (return, escape, tab, delete, space, arrows) with optional modifiers (command, shift, option, control) |
| `shake` | — | Trigger shake gesture (Ctrl+Cmd+Z) for undo/dev menus |
| `launch_app` | `name` | Open app by name via Spotlight search |
| `open_url` | `url` | Open URL in Safari |
| `press_home` | — | Go to home screen |
| `press_app_switcher` | — | Open app switcher |
| `spotlight` | — | Open Spotlight search |
| `get_orientation` | — | Report portrait/landscape and window dimensions |
| `status` | — | Connection state, window geometry, and device readiness |

## Coordinates

Coordinates are in points relative to the mirroring window's top-left corner. Use `describe_screen` to get exact tap coordinates via OCR — its grid overlay also helps target unlabeled icons (back arrows, stars, gears) that OCR can't detect. For raw screenshots, coordinates are Retina 2x — divide pixel coordinates by 2 to get tap coordinates.

## Typing Workflow

`type_text` and `press_key` route keyboard input through the Karabiner virtual HID keyboard via the helper daemon. If iPhone Mirroring isn't already frontmost, the MCP server activates it once (which may trigger a macOS Space switch) and stays there. Subsequent keyboard tool calls reuse the active window without switching again.

- Characters are mapped to USB HID keycodes with automatic keyboard layout translation — non-US layouts (French AZERTY, German QWERTZ, etc.) are supported via UCKeyTranslate
- iOS autocorrect applies — type carefully or disable it on the iPhone

## Key Press Workflow

`press_key` sends special keys that `type_text` can't handle — navigation keys, Return to submit forms, Escape to dismiss dialogs, Tab to switch fields, arrows to move through lists. Add modifiers for shortcuts like Cmd+N (new message) or Cmd+Z (undo).

For navigating within apps, combine `spotlight` + `type_text` + `press_key`. For example: `spotlight` → `type_text "Messages"` → `press_key return` → `press_key {"key":"n","modifiers":["command"]}` to open a new conversation.
