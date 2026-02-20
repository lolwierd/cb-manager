#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CBManager"
BUNDLE_NAME="$APP_NAME.app"
TARGET_APP="/Applications/$BUNDLE_NAME"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_APP="$ROOT_DIR/dist/$BUNDLE_NAME"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build-app.sh" "1.0.0"

if [[ ! -d "$DIST_APP" ]]; then
  echo "[cb-manager] Error: app bundle not found at $DIST_APP"
  exit 1
fi

# Stop running app before replacing
pkill -x CBManager 2>/dev/null || true

install_bundle() {
  rm -rf "$TARGET_APP"
  cp -R "$DIST_APP" "$TARGET_APP"
}

if [[ -w /Applications ]]; then
  install_bundle
else
  echo "[cb-manager] /Applications requires elevated privileges."
  sudo bash -c "rm -rf '$TARGET_APP' && cp -R '$DIST_APP' '$TARGET_APP'"
fi

echo "[cb-manager] Installed: $TARGET_APP"
echo "[cb-manager] Launching app..."
open "$TARGET_APP"
