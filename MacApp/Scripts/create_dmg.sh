#!/bin/bash
#
# Create a DMG installer for 7-Zip Mac
#
# Usage: ./create_dmg.sh [path/to/7-Zip.app] [output_dir]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACAPP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_PATH="${1:-}"
OUTPUT_DIR="${2:-$MACAPP_DIR/build}"
APP_NAME="SeptaZip"
DMG_NAME="SeptaZip"
VOLUME_NAME="SeptaZip"

# ── Locate the .app bundle ───────────────────────────────────────

if [ -z "$APP_PATH" ]; then
    # Try common locations
    for candidate in \
        "$MACAPP_DIR/DerivedData/Build/Products/Release/$APP_NAME.app" \
        "$MACAPP_DIR/build/Build/Products/Release/$APP_NAME.app" \
        "$MACAPP_DIR/build/archive/$APP_NAME.xcarchive/Products/Applications/$APP_NAME.app" \
        "$MACAPP_DIR/build/Release/$APP_NAME.app"; do
        if [ -d "$candidate" ]; then
            APP_PATH="$candidate"
            break
        fi
    done
fi

if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "ERROR: Could not find $APP_NAME.app"
    echo ""
    echo "Usage: $0 [path/to/7-Zip.app] [output_dir]"
    echo ""
    echo "Build the app first with one of:"
    echo "  make build-release"
    echo "  make archive"
    exit 1
fi

echo "=== Creating DMG ==="
echo "App:    $APP_PATH"
echo "Output: $OUTPUT_DIR"
echo ""

mkdir -p "$OUTPUT_DIR"

# Read version from the app's Info.plist
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0")
DMG_FILENAME="${DMG_NAME}-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_FILENAME"

# ── Create temporary DMG staging directory ────────────────────────

STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

echo "Staging DMG contents..."
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# ── Create the DMG ────────────────────────────────────────────────

echo "Creating DMG..."

# Remove existing DMG if present
rm -f "$DMG_PATH"

# Create DMG with hdiutil
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

echo ""
echo "=== DMG created ==="
echo "File: $DMG_PATH"
echo "Size: $(du -h "$DMG_PATH" | cut -f1)"
echo ""
echo "To install: open the DMG and drag SeptaZip to Applications."
echo ""
echo "To remove Gatekeeper quarantine:"
echo "  xattr -d com.apple.quarantine \"$DMG_PATH\""
