#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/StatusBoard/Resources/joker_right.png"
OUTPUT="$ROOT/StatusBoard/Resources/AppIcon.icns"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/status-board-icon.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ICONSET="$STAGING/AppIcon.iconset"
mkdir -p "$ICONSET"

# Center the artwork on a white rounded tile, preserving its original proportions.
cat > "$STAGING/render.swift" <<'SWIFT'
import Foundation
import CoreGraphics
import ImageIO

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fatalError("Cannot load icon source")
}
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
            bitsPerComponent: 8, bytesPerRow: pixels * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            fatalError("Cannot create icon canvas")
        }
        let canvas = CGFloat(pixels)
        let tile = CGRect(x: canvas * 0.06, y: canvas * 0.06,
            width: canvas * 0.88, height: canvas * 0.88)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.addPath(CGPath(roundedRect: tile, cornerWidth: canvas * 0.18,
            cornerHeight: canvas * 0.18, transform: nil))
        context.fillPath()
        let factor = canvas * 0.80 / CGFloat(max(image.width, image.height))
        let width = CGFloat(image.width) * factor
        let height = CGFloat(image.height) * factor
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: (CGFloat(pixels) - width) / 2,
            y: (CGFloat(pixels) - height) / 2, width: width, height: height))
        let suffix = scale == 2 ? "@2x" : ""
        let url = outputURL.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        guard let rendered = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            fatalError("Cannot create icon output")
        }
        CGImageDestinationAddImage(destination, rendered, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("Cannot save icon") }
    }
}
SWIFT
xcrun swift -module-cache-path "$STAGING/ModuleCache" "$STAGING/render.swift" "$SOURCE" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$OUTPUT"
echo "$OUTPUT"
