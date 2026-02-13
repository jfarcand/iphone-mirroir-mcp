# Troubleshooting

## Debug Mode

Pass `--debug` to enable verbose logging:

```bash
npx -y iphone-mirroir-mcp --debug
```

Logs are written to both stderr and `/tmp/iphone-mirroir-mcp-debug.log` (truncated on each startup). Logged events include permission checks, tap coordinates, focus state, and window geometry.

Tail the log in a separate terminal:

```bash
tail -f /tmp/iphone-mirroir-mcp-debug.log
```

Combine with permission bypass for full-access debugging:

```bash
npx -y iphone-mirroir-mcp --debug --yolo
```

## Common Issues

**`keyboard_ready: false`** — Karabiner's DriverKit extension isn't running. Open Karabiner-Elements, then go to **System Settings > General > Login Items & Extensions** and enable all toggles under Karabiner-Elements. You may need to enter your password.

**Typing goes to the wrong app instead of iPhone** — Make sure you're running v0.4.0+. The MCP server activates iPhone Mirroring via AppleScript before sending keystrokes through Karabiner. If this still fails, check that your terminal app has Accessibility permissions in System Settings.

**Taps don't register** — Check that the helper is running:
```bash
echo '{"action":"status"}' | nc -U /var/run/iphone-mirroir-helper.sock
```
If not responding, restart: `sudo brew services restart iphone-mirroir-mcp` or `sudo ./scripts/reinstall-helper.sh`.

**"Mirroring paused" screenshots** — The MCP server auto-resumes paused sessions. If it persists, click the iPhone Mirroring window manually once.

**iOS autocorrect mangling typed text** — iOS applies autocorrect to typed text. Disable autocorrect in iPhone Settings > General > Keyboard, or type words followed by spaces to confirm them before autocorrect triggers.
