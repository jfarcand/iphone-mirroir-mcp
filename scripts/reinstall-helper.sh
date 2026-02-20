#!/bin/bash
# ABOUTME: Reinstall the helper daemon with the latest build.
# ABOUTME: Must be run as root (sudo ./scripts/reinstall-helper.sh).

set -e

BINARY_SRC=".build/release/mirroir-helper"
BINARY_DST="/usr/local/bin/mirroir-helper"
PLIST="/Library/LaunchDaemons/com.jfarcand.mirroir-helper.plist"
LABEL="com.jfarcand.mirroir-helper"

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: must run as root (sudo $0)"
    exit 1
fi

if [ ! -f "$BINARY_SRC" ]; then
    echo "Error: $BINARY_SRC not found. Run 'swift build -c release' first."
    exit 1
fi

echo "Stopping helper..."
launchctl bootout "system/$LABEL" 2>/dev/null || true
sleep 2

# Kill any lingering process
pkill -9 -f mirroir-helper 2>/dev/null || true
sleep 1

echo "Copying binary..."
cp "$BINARY_SRC" "$BINARY_DST"
chmod 755 "$BINARY_DST"

# Clean up stale socket
rm -f /var/run/mirroir-helper.sock

echo "Starting helper..."
if ! launchctl bootstrap system "$PLIST" 2>/dev/null; then
    echo "Bootstrap failed, trying kickstart..."
    launchctl kickstart -k "system/$LABEL" 2>/dev/null || true
fi

sleep 2
echo "Checking status..."
echo '{"action":"status"}' | nc -U /var/run/mirroir-helper.sock
echo ""
echo "Done."
