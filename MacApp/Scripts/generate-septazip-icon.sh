#!/bin/bash
#
# Generate a modern SeptaZip app icon.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/../SevenZipMac/Resources/Assets.xcassets/AppIcon.appiconset"
MODULE_CACHE_DIR="$SCRIPT_DIR/../build/swift-module-cache"

mkdir -p "$OUTPUT_DIR"
mkdir -p "$MODULE_CACHE_DIR"

echo "=== Generating SeptaZip App Icon ==="

xcrun swift -module-cache-path "$MODULE_CACHE_DIR" - "$OUTPUT_DIR" <<'SWIFT_CODE'
import AppKit

let outputDir = CommandLine.arguments[1]
let sizes = [16, 32, 64, 128, 256, 512, 1024]

let bgTop = NSColor(calibratedRed: 0.98, green: 0.88, blue: 0.66, alpha: 1.0)
let bgMid = NSColor(calibratedRed: 0.95, green: 0.67, blue: 0.39, alpha: 1.0)
let bgBottom = NSColor(calibratedRed: 0.88, green: 0.42, blue: 0.24, alpha: 1.0)
let sunCore = NSColor(calibratedRed: 1.00, green: 0.97, blue: 0.84, alpha: 0.95)
let sunEdge = NSColor(calibratedRed: 0.99, green: 0.78, blue: 0.45, alpha: 0.72)
let plateTop = NSColor(calibratedRed: 0.24, green: 0.31, blue: 0.45, alpha: 1.0)
let plateBottom = NSColor(calibratedRed: 0.11, green: 0.16, blue: 0.27, alpha: 1.0)
let plateGlow = NSColor(calibratedRed: 0.61, green: 0.70, blue: 0.90, alpha: 0.20)
let accentTop = NSColor(calibratedRed: 0.99, green: 0.99, blue: 1.00, alpha: 1.0)
let accentMid = NSColor(calibratedRed: 0.84, green: 0.89, blue: 0.96, alpha: 1.0)
let accentBottom = NSColor(calibratedRed: 0.64, green: 0.71, blue: 0.81, alpha: 1.0)
let zipperTrack = NSColor(calibratedRed: 0.20, green: 0.23, blue: 0.33, alpha: 0.92)
let zipperLight = NSColor(calibratedRed: 0.89, green: 0.92, blue: 0.96, alpha: 1.0)
let zipperDark = NSColor(calibratedRed: 0.57, green: 0.64, blue: 0.74, alpha: 1.0)
let outline = NSColor(calibratedWhite: 1.0, alpha: 0.18)

func scaledRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in size: CGFloat) -> CGRect {
    CGRect(x: x * size, y: y * size, width: w * size, height: h * size)
}

func point(_ x: CGFloat, _ y: CGFloat, in size: CGFloat) -> CGPoint {
    CGPoint(x: x * size, y: y * size)
}

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat, in size: CGFloat) -> NSBezierPath {
    let rect = scaledRect(x, y, w, h, in: size)
    return NSBezierPath(roundedRect: rect, xRadius: radius * size, yRadius: radius * size)
}

func ribbonPath(from start: CGPoint, to end: CGPoint, width: CGFloat) -> NSBezierPath {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(sqrt(dx * dx + dy * dy), 0.0001)
    let px = -dy / length * width / 2
    let py = dx / length * width / 2

    let path = NSBezierPath()
    path.move(to: CGPoint(x: start.x + px, y: start.y + py))
    path.line(to: CGPoint(x: start.x - px, y: start.y - py))
    path.line(to: CGPoint(x: end.x - px, y: end.y - py))
    path.line(to: CGPoint(x: end.x + px, y: end.y + py))
    path.close()
    return path
}

func fill(_ path: NSBezierPath, colors: [NSColor], angle: CGFloat) {
    let gradient = NSGradient(colors: colors) ?? NSGradient(starting: colors[0], ending: colors[colors.count - 1])!
    gradient.draw(in: path, angle: angle)
}

func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat) {
    color.setStroke()
    path.lineWidth = width
    path.stroke()
}

func rotatedRoundedRect(center: CGPoint, width: CGFloat, height: CGFloat, radius: CGFloat, angle: CGFloat) -> NSBezierPath {
    let rect = CGRect(
        x: center.x - width / 2,
        y: center.y - height / 2,
        width: width,
        height: height
    )
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    var transform = AffineTransform()
    transform.translate(x: center.x, y: center.y)
    transform.rotate(byRadians: angle)
    transform.translate(x: -center.x, y: -center.y)
    path.transform(using: transform)
    return path
}

func drawBackground(size: CGFloat) {
    let bounds = CGRect(x: 0, y: 0, width: size, height: size)
    let iconMask = NSBezierPath(roundedRect: bounds, xRadius: size * 0.235, yRadius: size * 0.235)
    iconMask.addClip()

    fill(iconMask, colors: [bgTop, bgMid, bgBottom], angle: -90)

    let sun = NSBezierPath(ovalIn: scaledRect(0.18, 0.17, 0.64, 0.64, in: size))
    fill(sun, colors: [sunCore, sunEdge], angle: -90)

    for inset in [0.01, 0.06, 0.11] {
        let ringRect = scaledRect(0.18 + inset, 0.17 + inset, 0.64 - inset * 2, 0.64 - inset * 2, in: size)
        let ring = NSBezierPath(ovalIn: ringRect)
        stroke(ring, color: NSColor(calibratedWhite: 1.0, alpha: 0.12), width: size * 0.01)
    }

    let stripeY = [0.18, 0.31, 0.44, 0.57, 0.70]
    for y in stripeY {
        let stripe = roundedRect(0.0, y, 1.0, 0.032, radius: 0.01, in: size)
        fill(stripe, colors: [
            NSColor(calibratedWhite: 1.0, alpha: 0.10),
            NSColor(calibratedWhite: 1.0, alpha: 0.02)
        ], angle: 0)
    }

    let sweep = NSBezierPath()
    sweep.move(to: point(0.60, 0.90, in: size))
    sweep.line(to: point(0.95, 0.58, in: size))
    sweep.line(to: point(0.95, 0.50, in: size))
    sweep.line(to: point(0.54, 0.84, in: size))
    sweep.close()
    fill(sweep, colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.38),
        NSColor(calibratedWhite: 1.0, alpha: 0.00)
    ], angle: -25)

    let cornerGlow = NSBezierPath(ovalIn: scaledRect(-0.06, 0.64, 0.42, 0.42, in: size))
    fill(cornerGlow, colors: [
        NSColor(calibratedWhite: 1.0, alpha: 0.16),
        NSColor(calibratedWhite: 1.0, alpha: 0.0)
    ], angle: -90)

    stroke(iconMask, color: outline, width: max(1.0, size * 0.013))
}

func drawPlate(size: CGFloat) {
    let shadow = NSShadow()
    shadow.shadowBlurRadius = size * 0.08
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.03)
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.26)

    let plate = roundedRect(0.18, 0.16, 0.64, 0.68, radius: 0.18, in: size)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    fill(plate, colors: [plateTop, plateBottom], angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let glow = roundedRect(0.205, 0.57, 0.59, 0.21, radius: 0.14, in: size)
    fill(glow, colors: [plateGlow, NSColor.clear], angle: -90)

    stroke(plate, color: NSColor(calibratedWhite: 1.0, alpha: 0.14), width: max(1.0, size * 0.009))
}

func drawGlyph(size: CGFloat) {
    let topBar = roundedRect(0.29, 0.66, 0.38, 0.11, radius: 0.055, in: size)
    let ribbon = ribbonPath(
        from: point(0.59, 0.64, in: size),
        to: point(0.44, 0.22, in: size),
        width: size * 0.132
    )

    let glyphShadow = NSShadow()
    glyphShadow.shadowBlurRadius = size * 0.04
    glyphShadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    glyphShadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.20)

    NSGraphicsContext.saveGraphicsState()
    glyphShadow.set()
    fill(topBar, colors: [accentTop, accentMid, accentBottom], angle: -90)
    fill(ribbon, colors: [accentTop, accentMid, accentBottom], angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    stroke(topBar, color: NSColor(calibratedWhite: 1.0, alpha: 0.22), width: max(1.0, size * 0.006))
    stroke(ribbon, color: NSColor(calibratedWhite: 1.0, alpha: 0.18), width: max(1.0, size * 0.006))
    stroke(topBar, color: NSColor(calibratedRed: 0.34, green: 0.40, blue: 0.50, alpha: 0.28), width: max(1.0, size * 0.009))
    stroke(ribbon, color: NSColor(calibratedRed: 0.34, green: 0.40, blue: 0.50, alpha: 0.24), width: max(1.0, size * 0.009))

    let track = ribbonPath(
        from: point(0.58, 0.60, in: size),
        to: point(0.45, 0.30, in: size),
        width: size * 0.05
    )
    fill(track, colors: [zipperTrack, NSColor(calibratedWhite: 0.05, alpha: 0.86)], angle: -90)

    let start = point(0.60, 0.60, in: size)
    let end = point(0.45, 0.30, in: size)
    let dx = end.x - start.x
    let dy = end.y - start.y
    let angle = atan2(dy, dx)
    let length = sqrt(dx * dx + dy * dy)
    let ux = dx / length
    let uy = dy / length
    let px = -uy
    let py = ux

    for index in 0..<7 {
        let t = CGFloat(index) / 6.0
        let center = CGPoint(
            x: start.x + dx * t,
            y: start.y + dy * t
        )
        let offset = (index % 2 == 0 ? 1.0 : -1.0) * size * 0.018
        let toothCenter = CGPoint(
            x: center.x + px * offset,
            y: center.y + py * offset
        )
        let tooth = rotatedRoundedRect(
            center: toothCenter,
            width: size * 0.055,
            height: size * 0.017,
            radius: size * 0.007,
            angle: angle
        )
        fill(tooth, colors: [zipperLight, zipperDark], angle: -90)
    }

    let pull = rotatedRoundedRect(
        center: point(0.43, 0.22, in: size),
        width: size * 0.06,
        height: size * 0.085,
        radius: size * 0.022,
        angle: angle
    )
    fill(pull, colors: [zipperLight, zipperDark], angle: -90)

    let pullCut = rotatedRoundedRect(
        center: point(0.43, 0.22, in: size),
        width: size * 0.026,
        height: size * 0.047,
        radius: size * 0.01,
        angle: angle
    )
    NSColor(calibratedRed: 0.34, green: 0.41, blue: 0.52, alpha: 0.95).setFill()
    pullCut.fill()
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    drawBackground(size: size)
    drawPlate(size: size)
    drawGlyph(size: size)

    image.unlockFocus()
    return image
}

for size in sizes {
    let icon = drawIcon(size: CGFloat(size))

    guard let tiffData = icon.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to render icon at \(size)x\(size)")
    }

    let filename = "\(outputDir)/icon_\(size)x\(size).png"
    try pngData.write(to: URL(fileURLWithPath: filename))
    print("Generated: icon_\(size)x\(size).png")
}

let contentsJSON = """
{
  "images" : [
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_16x16.png", "scale" : "1x" },
    { "size" : "16x16", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "2x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_32x32.png", "scale" : "1x" },
    { "size" : "32x32", "idiom" : "mac", "filename" : "icon_64x64.png", "scale" : "2x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_128x128.png", "scale" : "1x" },
    { "size" : "128x128", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "2x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_256x256.png", "scale" : "1x" },
    { "size" : "256x256", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "2x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_512x512.png", "scale" : "1x" },
    { "size" : "512x512", "idiom" : "mac", "filename" : "icon_1024x1024.png", "scale" : "2x" }
  ],
  "info" : {
    "version" : 1,
    "author" : "xcode"
  }
}
"""

try contentsJSON.write(
    to: URL(fileURLWithPath: "\(outputDir)/Contents.json"),
    atomically: true,
    encoding: .utf8
)

print("Generated: Contents.json")
print("✓ SeptaZip modern icon generation complete")
SWIFT_CODE

echo ""
echo "Icon generated at: $OUTPUT_DIR"
