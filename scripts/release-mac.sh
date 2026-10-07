#!/usr/bin/env bash
# Archives the Mac app, exports it signed with Developer ID (iCloud uses the Production
# CloudKit environment), notarizes it when NOTARY_PROFILE is set, and zips it for a GitHub release.
#
# One-time notarization setup (stores credentials in your keychain):
#   xcrun notarytool store-credentials countdownula --apple-id <you> --team-id YZ36Z8GSEN
# Then:
#   NOTARY_PROFILE=countdownula scripts/release-mac.sh
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=$(awk '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
TEAM=$(awk '/DEVELOPMENT_TEAM:/ {print $2; exit}' project.yml)
ARCHIVE=build/Countdownula.xcarchive
EXPORT=build/export

xcodegen generate --quiet
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -project Countdownula.xcodeproj -scheme Countdownula -configuration Release \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates -quiet archive

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
