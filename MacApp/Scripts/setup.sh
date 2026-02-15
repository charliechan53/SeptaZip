#!/bin/bash
#
# Setup script for 7-Zip Mac App development
# Installs dependencies and prepares the build environment.
#
# Usage: ./setup.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== 7-Zip Mac App Setup ==="
echo ""

# Check macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "ERROR: This script must be run on macOS"
    exit 1
fi

# Check for Xcode command line tools
if ! xcode-select -p &>/dev/null; then
    echo "Installing Xcode Command Line Tools..."
    xcode-select --install
    echo "Please complete the installation and re-run this script."
    exit 0
fi
echo "[OK] Xcode Command Line Tools"

# Check for Xcode
if ! [ -d "/Applications/Xcode.app" ]; then
    echo "WARNING: Xcode.app not found. You need Xcode to build the macOS app."
    echo "         Install from: https://apps.apple.com/app/xcode/id497799835"
fi

# Check for XcodeGen (optional, for regenerating project)
if command -v xcodegen &>/dev/null; then
    echo "[OK] XcodeGen found"
else
    echo "[--] XcodeGen not found (optional - install with: brew install xcodegen)"
fi

# Check architecture
ARCH=$(uname -m)
echo "[OK] Architecture: $ARCH"

# Build 7zz binary
echo ""
echo "--- Building 7zz binary ---"
"$SCRIPT_DIR/build_7zz.sh" arm64 "$APP_DIR/build"

# Copy binary into app resources
mkdir -p "$APP_DIR/SevenZipMac/Resources"
cp "$APP_DIR/build/7zz" "$APP_DIR/SevenZipMac/Resources/7zz"
echo "[OK] 7zz binary copied to app resources"

# Generate Xcode project if XcodeGen is available
if command -v xcodegen &>/dev/null; then
    echo ""
    echo "--- Generating Xcode project ---"
    cd "$APP_DIR"
    xcodegen generate
    echo "[OK] Xcode project generated"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Open MacApp/SevenZipMac.xcodeproj in Xcode"
echo "     (or run: xcodegen generate && open SevenZipMac.xcodeproj)"
echo "  2. Select 'SevenZipMac' scheme and build (Cmd+B)"
echo "  3. Run the app (Cmd+R)"
echo ""
echo "To install Finder extension:"
echo "  1. Build and run the app"
echo "  2. Go to System Settings → Privacy & Security → Extensions → Finder"
echo "  3. Enable '7-Zip' extension"
