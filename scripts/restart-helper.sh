#!/bin/bash
# ABOUTME: Restart the mirroir-helper daemon via launchd.
# ABOUTME: Handles the stale-bootstrap race by booting out first, waiting, then re-bootstrapping.

set -e

PLIST="/Library/LaunchDaemons/com.jfarcand.mirroir-helper.plist"
SERVICE="system/com.jfarcand.mirroir-helper"
SOCKET="/var/run/mirroir-helper.sock"

if [ "$(id -u)" -ne 0 ]; then
    echo "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

echo "Stopping helper daemon..."
launchctl bootout "$SERVICE" 2>/dev/null || true

echo "Waiting for launchd to release service..."
sleep 2

# Clean stale socket
if [ -e "$SOCKET" ]; then
    rm -f "$SOCKET"
    echo "Removed stale socket: $SOCKET"
fi

echo "Starting helper daemon..."
launchctl bootstrap system "$PLIST"

# Wait for socket to appear and daemon to respond
for i in $(seq 1 15); do
    if [ -e "$SOCKET" ]; then
        # Verify the daemon actually responds (not just socket exists)
        RESP=$(python3 -c "
import socket, json, sys
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    s.connect('$SOCKET')
    s.sendall(json.dumps({'action': 'status'}).encode() + b'\n')
    s.settimeout(2)
    print(s.recv(4096).decode().strip())
except:
    pass
finally:
    s.close()
" 2>/dev/null)
        if echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'ok' in d else 1)" 2>/dev/null; then
            echo "Helper daemon running and responding"
            exit 0
        fi
        echo "Socket exists but daemon not responding yet (attempt $i/15)..."
    fi
    sleep 1
done

echo "Warning: daemon not responding after 15s — check: sudo launchctl list | grep mirroir"
exit 1
