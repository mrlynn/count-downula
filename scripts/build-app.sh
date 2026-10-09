#!/usr/bin/env bash
# Builds a signed Countdownula.app into ./build using your Apple Developer team (see project.yml).
# Usage: scripts/build-app.sh [release|debug]
# For a notarized, distributable build use scripts/release-mac.sh instead.
set -euo pipefail

cd "$(dirname "$0")/.."
case "${1:-release}" in
  debug|Debug) CONFIG=Debug ;;
  *) CONFIG=Release ;;
esac

xcodegen generate --quiet
# DIRECT=1 builds the GitHub flavor (always unlocked, not sandboxed) instead of the Mac App Store one.
OVERRIDES=()
if [[ "${DIRECT:-0}" == "1" ]]; then
  OVERRIDES=(SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION'
             MAC_APP_ENTITLEMENTS=Resources/CountdownulaDirect.entitlements)
fi
xcodebuild -project Countdownula.xcodeproj -scheme Countdownula -configuration "$CONFIG" \
  -derivedDataPath .build/xcode -allowProvisioningUpdates ${OVERRIDES[@]+"${OVERRIDES[@]}"} -quiet build

rm -rf build/Countdownula.app
mkdir -p build
cp -R ".build/xcode/Build/Products/$CONFIG/Countdownula.app" build/
echo "Built build/Countdownula.app ($CONFIG)"
