#!/bin/bash
#
# Generate app icon from SVG or create a simple programmatic icon.
# Run this on macOS to generate the AppIcon assets.
#
# Usage: ./generate-icons.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICON_DIR="$SCRIPT_DIR/../SevenZipMac/Resources/Assets.xcassets/AppIcon.appiconset"

mkdir -p "$ICON_DIR"

# Generate a simple icon using Python/Pillow if available,
# otherwise use sips to create placeholder icons.

generate_with_sips() {
    # Create a simple colored square icon as a starting point
    # Users should replace with proper artwork

    local SIZES=(16 32 64 128 256 512 1024)

    for size in "${SIZES[@]}"; do
        # Create a simple icon using Swift
        swift - "$size" "$ICON_DIR/icon_${size}x${size}.png" << 'SWIFT'
import Cocoa

let args = CommandLine.arguments
guard args.count >= 3,
      let size = Int(args[1]) else {
    print("Usage: generate size output.png")
    exit(1)
}
let outputPath = args[2]

let cgSize = CGSize(width: size, height: size)
let image = NSImage(size: cgSize)
image.lockFocus()

// Background - rounded rectangle
let bgRect = NSRect(origin: .zero, size: cgSize)
let cornerRadius = CGFloat(size) * 0.2
let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Gradient background
let gradient = NSGradient(starting: NSColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
                          ending: NSColor(red: 0.1, green: 0.2, blue: 0.6, alpha: 1.0))!
gradient.draw(in: bgPath, angle: -45)

// Draw "7z" text
let fontSize = CGFloat(size) * 0.42
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.boldSystemFont(ofSize: fontSize),
    .foregroundColor: NSColor.white
]
let text = "7z" as NSString
let textSize = text.size(withAttributes: attrs)
let textPoint = NSPoint(
    x: (CGFloat(size) - textSize.width) / 2,
    y: (CGFloat(size) - textSize.height) / 2 - CGFloat(size) * 0.02
)
text.draw(at: textPoint, withAttributes: attrs)

image.unlockFocus()

// Save as PNG
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    print("Failed to create PNG")
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try! pngData.write(to: url)
print("Created \(outputPath) (\(size)x\(size))")
SWIFT
    done

    # Update the Contents.json with filenames
    cat > "$ICON_DIR/Contents.json" << 'JSON'
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_64x64.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_1024x1024.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
JSON

    echo "Icons generated in $ICON_DIR"
}

generate_with_sips
