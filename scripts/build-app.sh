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
xcodebuild -project Countdownula.xcodeproj -scheme Countdownula -configuration "$CONFIG" \
  -derivedDataPath .build/xcode -allowProvisioningUpdates -quiet build

rm -rf build/Countdownula.app
mkdir -p build
cp -R ".build/xcode/Build/Products/$CONFIG/Countdownula.app" build/
echo "Built build/Countdownula.app ($CONFIG)"
