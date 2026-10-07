#!/usr/bin/env bash
# Builds Countdownula and wraps it into a signed (ad-hoc) .app bundle in ./build.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/Countdownula.app"

# Release builds are universal (Apple Silicon + Intel); debug builds stay native for speed.
ARCHS=()
[[ "$CONFIG" == "release" ]] && ARCHS=(--arch arm64 --arch x86_64)

swift build -c "$CONFIG" "${ARCHS[@]}"
BIN="$(swift build -c "$CONFIG" "${ARCHS[@]}" --show-bin-path)/Countdownula"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Countdownula"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuBarIcon.png Resources/MenuBarIcon@2x.png "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
