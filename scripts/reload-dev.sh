#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[cb-manager] Building debug binary..."
swift build
BIN_DIR="$(swift build --show-bin-path)"
BIN="$BIN_DIR/CBManager"

if [[ ! -x "$BIN" ]]; then
  echo "[cb-manager] Error: binary not found at $BIN"
  exit 1
fi

echo "[cb-manager] Stopping existing CBManager processes..."
pkill -x CBManager 2>/dev/null || true
sleep 0.2

LOG_FILE="/tmp/cbmanager-dev.log"
echo "[cb-manager] Starting $BIN"
nohup "$BIN" >"$LOG_FILE" 2>&1 &
PID=$!

sleep 0.3
if ps -p "$PID" >/dev/null 2>&1; then
  echo "[cb-manager] Running (pid=$PID)"
  echo "[cb-manager] Log: $LOG_FILE"
else
  echo "[cb-manager] Failed to start. Recent logs:"
  tail -n 50 "$LOG_FILE" || true
  exit 1
fi
