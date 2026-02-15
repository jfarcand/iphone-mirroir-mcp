#!/bin/bash
# ABOUTME: Packages the FakeMirroring binary into a macOS .app bundle for integration testing.
# ABOUTME: Creates the bundle structure, copies binary and Info.plist, verifies the bundle ID.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="${PROJECT_DIR}/.build/release"
APP_DIR="${BUILD_DIR}/FakeMirroring.app"
BINARY="${BUILD_DIR}/FakeMirroring"

# Verify binary exists
if [ ! -f "$BINARY" ]; then
    echo "ERROR: FakeMirroring binary not found at $BINARY"
    echo "Run: swift build -c release --product FakeMirroring"
    exit 1
fi

# Create app bundle structure
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy binary
cp "$BINARY" "${APP_DIR}/Contents/MacOS/FakeMirroring"

# Copy Info.plist
cp "${PROJECT_DIR}/Resources/FakeMirroring/Info.plist" "${APP_DIR}/Contents/"

# Verify bundle ID
BUNDLE_ID=$(defaults read "${APP_DIR}/Contents/Info" CFBundleIdentifier 2>/dev/null || echo "UNKNOWN")
if [ "$BUNDLE_ID" != "com.jfarcand.FakeMirroring" ]; then
    echo "ERROR: Bundle ID mismatch: expected com.jfarcand.FakeMirroring, got $BUNDLE_ID"
    exit 1
fi

echo "FakeMirroring.app packaged at: ${APP_DIR}"
echo "Bundle ID: ${BUNDLE_ID}"
