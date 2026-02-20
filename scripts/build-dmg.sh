#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CBManager"
BUNDLE_NAME="$APP_NAME.app"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"

VERSION="${1:-1.0.0}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build-app.sh" "$VERSION"

STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT

cp -R "$DIST_DIR/$BUNDLE_NAME" "$STAGE_DIR/$BUNDLE_NAME"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"

echo "[cb-manager] Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "CBManager" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

echo "[cb-manager] DMG ready: $DMG_PATH"
