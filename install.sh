#!/bin/bash
# ABOUTME: One-step installer for iphone-mirroir-mcp.
# ABOUTME: Builds both binaries, installs the helper daemon, and configures Karabiner.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST_NAME="com.jfarcand.iphone-mirroir-helper"
HELPER_BIN="iphone-mirroir-helper"
MCP_BIN="iphone-mirroir-mcp"
KARABINER_CONFIG="$HOME/.config/karabiner/karabiner.json"

cd "$SCRIPT_DIR"

# --- Step 1: Check prerequisites ---

echo "=== Checking prerequisites ==="

if ! command -v swift >/dev/null 2>&1; then
    echo "Error: Swift not found. Install Xcode Command Line Tools:"
    echo "  xcode-select --install"
    exit 1
fi

if ! ls /Library/Application\ Support/org.pqrs/tmp/rootonly/vhidd_server/*.sock >/dev/null 2>&1; then
    echo "Error: Karabiner-Elements not running."
    echo "  brew install --cask karabiner-elements"
    echo "  Then open Karabiner-Elements and approve the DriverKit extension."
    exit 1
fi

echo "Swift: $(swift --version 2>&1 | head -1)"
echo "Karabiner: running"

# --- Step 2: Build ---

echo ""
echo "=== Building ==="
swift build -c release

echo "Built: .build/release/$MCP_BIN"
echo "Built: .build/release/$HELPER_BIN"

# --- Step 3: Configure Karabiner ignore rule ---

echo ""
echo "=== Configuring Karabiner ==="

IGNORE_RULE='{"identifiers":{"is_keyboard":true,"product_id":592,"vendor_id":1452},"ignore":true}'

if [ -f "$KARABINER_CONFIG" ]; then
    if grep -q '"product_id": 592' "$KARABINER_CONFIG" 2>/dev/null || \
       grep -q '"product_id":592' "$KARABINER_CONFIG" 2>/dev/null; then
        echo "Karabiner ignore rule already configured."
    else
        # Add the device ignore rule to the first profile
        python3 -c "
import json, sys
with open('$KARABINER_CONFIG') as f:
    config = json.load(f)
profile = config['profiles'][0]
if 'devices' not in profile:
    profile['devices'] = []
profile['devices'].append(json.loads('$IGNORE_RULE'))
with open('$KARABINER_CONFIG', 'w') as f:
    json.dump(config, f, indent=4)
print('Added device ignore rule to Karabiner config.')
"
    fi
else
    mkdir -p "$(dirname "$KARABINER_CONFIG")"
    cat > "$KARABINER_CONFIG" << 'KARABINER_EOF'
{
    "profiles": [
        {
            "devices": [
                {
                    "identifiers": {
                        "is_keyboard": true,
                        "product_id": 592,
                        "vendor_id": 1452
                    },
                    "ignore": true
                }
            ],
            "name": "Default profile",
            "selected": true,
            "virtual_hid_keyboard": { "keyboard_type_v2": "ansi" }
        }
    ]
}
KARABINER_EOF
    echo "Created Karabiner config with device ignore rule."
fi

# --- Step 4: Install helper daemon ---

echo ""
echo "=== Installing helper daemon (requires sudo) ==="

sudo cp ".build/release/$HELPER_BIN" /usr/local/bin/
sudo chmod 755 "/usr/local/bin/$HELPER_BIN"

if sudo launchctl list "$PLIST_NAME" >/dev/null 2>&1; then
    echo "Stopping existing daemon..."
    sudo launchctl bootout system/"$PLIST_NAME" 2>/dev/null || true
    sleep 1
fi

sudo cp "Resources/$PLIST_NAME.plist" /Library/LaunchDaemons/
sudo chown root:wheel "/Library/LaunchDaemons/$PLIST_NAME.plist"
sudo chmod 644 "/Library/LaunchDaemons/$PLIST_NAME.plist"
sudo launchctl bootstrap system "/Library/LaunchDaemons/$PLIST_NAME.plist"

# Wait for helper to start and verify
sleep 2
STATUS=$(echo '{"action":"status"}' | nc -U /var/run/iphone-mirroir-helper.sock 2>/dev/null || echo '{"ok":false}')
echo "Helper status: $STATUS"

# --- Done ---

MCP_PATH="$(pwd)/.build/release/$MCP_BIN"

echo ""
echo "=== Done ==="
echo ""
echo "Add to your MCP client config (.mcp.json):"
echo ""
echo "  {"
echo "    \"mcpServers\": {"
echo "      \"iphone-mirroring\": {"
echo "        \"command\": \"$MCP_PATH\""
echo "      }"
echo "    }"
echo "  }"
echo ""
echo "Then grant Screen Recording + Accessibility permissions to your terminal."
