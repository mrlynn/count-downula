#!/usr/bin/env bash
# Archives the Mac app for the GitHub download, exports it signed with Developer ID (iCloud uses the Production
# CloudKit environment), notarizes it when NOTARY_PROFILE is set, and zips it for a GitHub release.
# The screensaver (Count Downcula.saver) is built, signed, notarized and zipped beside it: the Mac App
# Store doesn't take screensavers, and only this unsandboxed build can feed it countdowns.
#
# One-time notarization setup (stores credentials in your keychain):
#   xcrun notarytool store-credentials countdownula --apple-id <you> --team-id YZ36Z8GSEN
# Then:
#   NOTARY_PROFILE=countdownula scripts/release-mac.sh
set -euo pipefail

cd "$(dirname "$0")/.."
# VERSION=1.1.1 overrides the project's version, for a GitHub-only release between App Store versions.
VERSION=${VERSION:-$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)}
TEAM=$(awk '/DEVELOPMENT_TEAM:/ {print $2; exit}' project.yml)
ARCHIVE=build/Countdownula.xcarchive
EXPORT=build/export

xcodegen generate --quiet
rm -rf "$ARCHIVE" "$EXPORT"
# The GitHub download: always unlocked (no StoreKit) and not sandboxed. The project's own settings
# build the Mac App Store version; see scripts/release-mac-appstore.sh.
xcodebuild -project Countdownula.xcodeproj -scheme Countdownula -configuration Release \
  -archivePath "$ARCHIVE" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DIRECT_DISTRIBUTION' \
  MAC_APP_ENTITLEMENTS=Resources/CountdownulaDirect.entitlements \
  MARKETING_VERSION="$VERSION" \
  -allowProvisioningUpdates -quiet archive

cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist build/ExportOptions.plist -allowProvisioningUpdates -quiet

APP="$EXPORT/Countdownula.app"
ZIP="build/Countdownula-$VERSION.zip"
rm -f "$ZIP"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ditto -c -k --keepParent "$APP" build/notarize.zip
  xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm build/notarize.zip
else
  echo "NOTARY_PROFILE not set: skipping notarization (users will see a Gatekeeper warning)."
fi

ditto -c -k --keepParent "$APP" "$ZIP"
echo "Release ready: $ZIP"

# The screensaver: a plain bundle, signed with Developer ID and the hardened runtime, then notarized.
SAVER_BUILD=build/saver
SAVER="$SAVER_BUILD/Release/Count Downcula.saver"
SAVER_ZIP="build/Count-Downcula-Screensaver-$VERSION.zip"
rm -rf "$SAVER_BUILD" "$SAVER_ZIP"
xcodebuild -project Countdownula.xcodeproj -target CountdownculaSaver -configuration Release \
  SYMROOT="$PWD/$SAVER_BUILD" MARKETING_VERSION="$VERSION" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Developer ID Application" DEVELOPMENT_TEAM="$TEAM" \
  ENABLE_HARDENED_RUNTIME=YES OTHER_CODE_SIGN_FLAGS=--timestamp -quiet build
codesign --verify --strict "$SAVER"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ditto -c -k --keepParent "$SAVER" build/notarize-saver.zip
  xcrun notarytool submit build/notarize-saver.zip --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$SAVER"
  rm build/notarize-saver.zip
fi

ditto -c -k --keepParent "$SAVER" "$SAVER_ZIP"
echo "Screensaver ready: $SAVER_ZIP (double-click the .saver to install)"
