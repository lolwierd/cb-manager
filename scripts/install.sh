#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CBManager"
BUNDLE_NAME="$APP_NAME.app"
TARGET_APP="/Applications/$BUNDLE_NAME"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

echo "[cb-manager] Building release binary..."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN" ]]; then
  echo "[cb-manager] Error: release binary not found at $BIN"
  exit 1
fi

STAGE_DIR="$(mktemp -d)"
APP_DIR="$STAGE_DIR/$BUNDLE_NAME"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>CBManager</string>
  <key>CFBundleDisplayName</key>
  <string>CBManager</string>
  <key>CFBundleIdentifier</key>
  <string>com.cbmanager.app</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>CBManager</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Stop running app before replacing
pkill -x CBManager 2>/dev/null || true

install_bundle() {
  rm -rf "$TARGET_APP"
  cp -R "$APP_DIR" "$TARGET_APP"
}

if [[ -w /Applications ]]; then
  install_bundle
else
  echo "[cb-manager] /Applications requires elevated privileges."
  sudo bash -c "rm -rf '$TARGET_APP' && cp -R '$APP_DIR' '$TARGET_APP'"
fi

rm -rf "$STAGE_DIR"

echo "[cb-manager] Installed: $TARGET_APP"
echo "[cb-manager] Launching app..."
open "$TARGET_APP"
