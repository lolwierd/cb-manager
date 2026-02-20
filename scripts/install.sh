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
if pgrep -x CBManager >/dev/null 2>&1; then
  echo "[cb-manager] Killing running CBManager..."
  pkill -x CBManager 2>/dev/null || true
  # Wait up to 3s for it to exit
  for i in $(seq 1 30); do
    pgrep -x CBManager >/dev/null 2>&1 || break
    sleep 0.1
  done
  # Force kill if still alive
  if pgrep -x CBManager >/dev/null 2>&1; then
    pkill -9 -x CBManager 2>/dev/null || true
    sleep 0.2
  fi
fi

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
if ! open "$TARGET_APP"; then
  echo "[cb-manager] Could not auto-launch app (likely headless shell/session)."
fi
