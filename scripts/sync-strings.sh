#!/usr/bin/env bash
# Refreshes Resources/Localizable.xcstrings from the app's code: builds every app and extension so the
# compiler lists the text each one shows (.stringsdata), then merges that into the catalog. New
# strings arrive untranslated; strings no longer used are marked stale. Xcode does the same when you
# build in the IDE; this is for the command line and CI.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED=.build/strings
xcodegen generate -q
for pair in "Countdownula:platform=macOS" "CountdownulaiOS:generic/platform=iOS Simulator" \
            "CountdownulaWatch:generic/platform=watchOS Simulator" \
            "CountdownculaTV:generic/platform=tvOS Simulator"; do
  scheme=${pair%%:*}
  destination=${pair#*:}
  build() {
    xcodebuild build -project Countdownula.xcodeproj -scheme "$scheme" -destination "$destination" \
      -derivedDataPath "$DERIVED" CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=YES -quiet
  }
  # The Mac app and its widgets compile the same catalog, which now and then collides on the first try.
  build || build
done
# The screensaver has no scheme of its own; build its target into the same place.
xcodebuild build -project Countdownula.xcodeproj -target CountdownculaSaver -configuration Debug \
  OBJROOT="$PWD/$DERIVED/Build/Intermediates.noindex" SYMROOT="$PWD/$DERIVED/Build/Products" \
  ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=YES -quiet

files=()
while IFS= read -r -d '' file; do files+=(--stringsdata "$file"); done \
  < <(find "$DERIVED/Build/Intermediates.noindex" -name '*.stringsdata' -print0)
xcrun xcstringstool sync Resources/Localizable.xcstrings "${files[@]}"
echo "Synced $(xcrun xcstringstool print Resources/Localizable.xcstrings | grep -c '^') strings into Resources/Localizable.xcstrings"
