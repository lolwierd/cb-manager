#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RES_DIR="$ROOT_DIR/Resources"
ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
BASE_PNG="$(mktemp -d)/AppIcon-1024.png"

mkdir -p "$RES_DIR" "$ICONSET_DIR"

swift - <<'SWIFT' "$BASE_PNG"
import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.07, green: 0.49, blue: 0.93, alpha: 1),
    NSColor(calibratedRed: 0.20, green: 0.27, blue: 0.96, alpha: 1)
])!
gradient.draw(in: NSBezierPath(roundedRect: rect, xRadius: 220, yRadius: 220), angle: -90)

let glowRect = rect.insetBy(dx: 80, dy: 80)
NSColor.white.withAlphaComponent(0.16).setFill()
NSBezierPath(roundedRect: glowRect, xRadius: 170, yRadius: 170).fill()

let symbolConfig = NSImage.SymbolConfiguration(pointSize: 430, weight: .bold)
if let symbol = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: nil)?.withSymbolConfiguration(symbolConfig) {
    let symbolRect = NSRect(x: 250, y: 225, width: 524, height: 574)
    symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 0.95)
}

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [.compressionFactor: 1.0]) {
    try png.write(to: output)
}
SWIFT

create_icon() {
  local px="$1"
  local name="$2"
  sips -z "$px" "$px" "$BASE_PNG" --out "$ICONSET_DIR/$name" >/dev/null
}

create_icon 16 icon_16x16.png
create_icon 32 icon_16x16@2x.png
create_icon 32 icon_32x32.png
create_icon 64 icon_32x32@2x.png
create_icon 128 icon_128x128.png
create_icon 256 icon_128x128@2x.png
create_icon 256 icon_256x256.png
create_icon 512 icon_256x256@2x.png
create_icon 512 icon_512x512.png
create_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$RES_DIR/AppIcon.icns"
cp "$BASE_PNG" "$RES_DIR/AppIcon-1024.png"

echo "Generated icon: $RES_DIR/AppIcon.icns"
