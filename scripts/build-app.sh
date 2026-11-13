#!/usr/bin/env bash
# Wraps the SwiftPM executable into TossBar.app. Xcode is not required.
#
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/TossBar.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/TossBar"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/TossBar"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature. Required for registering as a login item.
codesign --force --deep --sign - "$APP" >/dev/null

echo "Built $APP"
echo "  Run:     open \"$APP\""
echo "  Install: cp -R \"$APP\" /Applications/"
