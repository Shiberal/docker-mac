#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${NATIVESTACK_API_PORT:-7842}"

echo "Building nativestack backend…"
cd "$ROOT"
swift build -c release

API_BIN="$ROOT/.build/release/nativestack"
GUI_DIR="$ROOT/gui"

if lsof -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "API already listening on port $PORT"
else
  echo "Starting API on http://127.0.0.1:$PORT"
  "$API_BIN" serve --port "$PORT" &
  API_PID=$!
  trap 'kill "$API_PID" 2>/dev/null || true' EXIT
  sleep 1
fi

cd "$GUI_DIR"

if [ ! -d macos/Pods ]; then
  echo "Installing CocoaPods dependencies…"
  RCT_NEW_ARCH_ENABLED=1 pod install --project-directory=macos
fi

echo "Launching React Native macOS app…"
RCT_NEW_ARCH_ENABLED=1 npx react-native run-macos
