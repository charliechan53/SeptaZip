#!/bin/bash
#
# Build 7zz (7-Zip console) for macOS Apple Silicon (ARM64)
# This script compiles the 7zz binary from the 7-Zip source tree.
#
# Usage: ./build_7zz.sh [--arch arm64|x64|universal] [--output DIR]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BUNDLES_DIR="$ROOT_DIR/CPP/7zip/Bundles/Alone2"

ARCH="${1:-arm64}"
OUTPUT_DIR="${2:-$SCRIPT_DIR/../build}"

echo "=== Building 7zz for macOS ==="
echo "Architecture: $ARCH"
echo "Source root:  $ROOT_DIR"
echo "Output dir:   $OUTPUT_DIR"
echo ""

mkdir -p "$OUTPUT_DIR"

build_arch() {
    local arch="$1"
    local build_subdir="b/mac_${arch}"
    local build_dir="$BUNDLES_DIR/$build_subdir"
    local makefile_var

    if [ "$arch" = "arm64" ]; then
        makefile_var="cmpl_mac_arm64"
    else
        makefile_var="cmpl_mac_x64"
    fi

    echo "--- Building for $arch ---"

    # Build using the existing makefile system
    cd "$BUNDLES_DIR"

    # The 7-Zip build system uses make with specific variable files
    # We need to set the right compiler and flags for macOS
    make -j$(sysctl -n hw.ncpu 2>/dev/null || echo 4) \
        -f makefile.gcc \
        DISABLE_RAR_COMPRESS=1 \
        MY_ARCH="-arch $arch" \
        USE_ASM= \
        CC="clang -arch $arch" \
        CXX="clang++ -arch $arch" \
        O="$build_subdir" \
        2>&1

    if [ -f "$build_dir/7zz" ]; then
        echo "Successfully built 7zz for $arch at $build_dir/7zz"
        return 0
    else
        echo "ERROR: Build failed for $arch (expected at $build_dir/7zz)"
        ls -la "$build_dir/" 2>/dev/null || echo "Build directory does not exist"
        return 1
    fi
}

case "$ARCH" in
    arm64)
        build_arch "arm64"
        mkdir -p "$OUTPUT_DIR"
        cp "$BUNDLES_DIR/b/mac_arm64/7zz" "$OUTPUT_DIR/7zz"
        ;;
    x64)
        build_arch "x86_64"
        mkdir -p "$OUTPUT_DIR"
        cp "$BUNDLES_DIR/b/mac_x86_64/7zz" "$OUTPUT_DIR/7zz"
        ;;
    universal)
        build_arch "arm64"
        build_arch "x86_64"
        echo "--- Creating universal binary ---"
        mkdir -p "$OUTPUT_DIR"
        lipo -create \
            "$BUNDLES_DIR/b/mac_arm64/7zz" \
            "$BUNDLES_DIR/b/mac_x86_64/7zz" \
            -output "$OUTPUT_DIR/7zz"
        echo "Created universal binary"
        ;;
    *)
        echo "Unknown architecture: $ARCH"
        echo "Usage: $0 [arm64|x64|universal] [output_dir]"
        exit 1
        ;;
esac

chmod +x "$OUTPUT_DIR/7zz"
echo ""
echo "=== Build complete ==="
echo "Binary: $OUTPUT_DIR/7zz"
file "$OUTPUT_DIR/7zz"
"$OUTPUT_DIR/7zz" --help 2>&1 | head -5 || true
