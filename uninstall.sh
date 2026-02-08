#!/bin/bash
# ABOUTME: Full uninstaller for iphone-mirroir-mcp.
# ABOUTME: Removes helper daemon, Karabiner config changes, and optionally Karabiner-Elements itself.

set -e

PLIST_NAME="com.jfarcand.iphone-mirroir-helper"
HELPER_BIN="iphone-mirroir-helper"
KARABINER_CONFIG="$HOME/.config/karabiner/karabiner.json"

echo "=== Uninstalling iphone-mirroir-mcp ==="

# --- Step 1: Stop and remove helper daemon ---

echo ""
echo "--- Helper daemon ---"

if sudo launchctl list "$PLIST_NAME" >/dev/null 2>&1; then
    echo "Stopping daemon..."
    sudo launchctl bootout system/"$PLIST_NAME" 2>/dev/null || true
    sleep 1
fi

sudo rm -f "/usr/local/bin/$HELPER_BIN"
sudo rm -f "/Library/LaunchDaemons/$PLIST_NAME.plist"
sudo rm -f "/var/run/iphone-mirroir-helper.sock"
sudo rm -f "/var/log/iphone-mirroir-helper.log"
echo "Helper daemon removed."

# --- Step 2: Remove Karabiner ignore rule ---

echo ""
echo "--- Karabiner config ---"

if [ -f "$KARABINER_CONFIG" ]; then
    if grep -q '"product_id": 592' "$KARABINER_CONFIG" 2>/dev/null || \
       grep -q '"product_id":592' "$KARABINER_CONFIG" 2>/dev/null; then
        python3 -c "
import json
with open('$KARABINER_CONFIG') as f:
    config = json.load(f)
for profile in config.get('profiles', []):
    devices = profile.get('devices', [])
    profile['devices'] = [
        d for d in devices
        if not (d.get('identifiers', {}).get('product_id') == 592
                and d.get('identifiers', {}).get('vendor_id') == 1452)
    ]
with open('$KARABINER_CONFIG', 'w') as f:
    json.dump(config, f, indent=4)
print('Removed iPhone Mirroring ignore rule from Karabiner config.')
"
    else
        echo "No iPhone Mirroring ignore rule found in Karabiner config."
    fi
else
    echo "No Karabiner config found."
fi

# --- Step 3: Optionally remove Karabiner-Elements ---

echo ""
if [ -d "/Applications/Karabiner-Elements.app" ]; then
    read -p "Also uninstall Karabiner-Elements? [y/N] " answer
    case "$answer" in
        [yY]*)
            echo ""
            echo "--- Removing Karabiner-Elements ---"

            # Stop user-level agents
            for agent in \
                org.pqrs.service.agent.Karabiner-Menu \
                org.pqrs.service.agent.Karabiner-Core-Service \
                org.pqrs.service.agent.Karabiner-NotificationWindow \
                org.pqrs.service.agent.karabiner_console_user_server \
                org.pqrs.service.agent.karabiner_session_monitor; do
                launchctl remove "$agent" 2>/dev/null || true
            done

            # Stop system-level daemons
            for daemon in \
                org.pqrs.Karabiner-DriverKit-VirtualHIDDeviceClient \
                org.pqrs.karabiner.karabiner_core_service \
                org.pqrs.karabiner.karabiner_session_monitor; do
                sudo launchctl bootout system/"$daemon" 2>/dev/null || true
            done

            # Remove applications
            sudo rm -rf /Applications/Karabiner-Elements.app
            sudo rm -rf /Applications/Karabiner-EventViewer.app

            # Remove support files
            sudo rm -rf "/Library/Application Support/org.pqrs"

            # Remove user config
            rm -rf "$HOME/.config/karabiner"

            # Remove launch plists
            sudo rm -f /Library/LaunchDaemons/org.pqrs.*.plist
            sudo rm -f /Library/LaunchAgents/org.pqrs.*.plist
            rm -f "$HOME/Library/LaunchAgents/org.pqrs.*.plist"

            echo "Karabiner-Elements removed."
            echo "Note: The DriverKit system extension may remain until next reboot."
            ;;
        *)
            echo "Keeping Karabiner-Elements installed."
            ;;
    esac
fi

echo ""
echo "=== Uninstall complete ==="
