#!/usr/bin/env bash
# Archives the iPhone/iPad app and uploads it to App Store Connect, where it shows up in
# TestFlight after processing (usually 5-30 minutes).
#
# One-time setup:
#   1. Create the app record in App Store Connect (bundle ID com.countdownula.app).
#   2. Be signed in to your Apple ID in Xcode > Settings > Accounts, or set API key auth:
#        ASC_KEY_ID=... ASC_ISSUER_ID=... ASC_KEY_PATH=~/.appstoreconnect/AuthKey_XXXX.p8
#
# Every upload needs a new build number. Pass one, or it uses a timestamp:
#   scripts/release-ios.sh          # build number = YYYYMMDDHHMM
#   scripts/release-ios.sh 3        # build number = 3
#   UPLOAD=0 scripts/release-ios.sh # archive + export an .ipa only, no upload
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM=$(awk '/DEVELOPMENT_TEAM:/ {print $2; exit}' project.yml)
BUILD_NUMBER=${1:-$(date +%Y%m%d%H%M)}
ARCHIVE=build/CountdownulaiOS.xcarchive
EXPORT=build/export-ios

AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        -authenticationKeyPath "$ASC_KEY_PATH")
fi

xcodegen generate --quiet
rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p build
xcodebuild -project Countdownula.xcodeproj -scheme CountdownulaiOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} -quiet archive

DESTINATION=upload
[[ "${UPLOAD:-1}" == "0" ]] && DESTINATION=export

cat > build/ExportOptions-ios.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>destination</key><string>$DESTINATION</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
    <key>uploadSymbols</key><true/>
    <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist build/ExportOptions-ios.plist \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [[ "$DESTINATION" == "upload" ]]; then
  echo "Uploaded build $BUILD_NUMBER. It appears in App Store Connect > TestFlight once processed."
else
  echo "Exported: $EXPORT (build $BUILD_NUMBER)"
fi
