#!/usr/bin/env bash
# Archives the Mac app for the Mac App Store (sandboxed, with the free tier and the Unlimited purchase)
# and uploads it to App Store Connect, where it can be picked for the macOS version once processed.
# The GitHub download is built by scripts/release-mac.sh instead.
#
# Auth is the same as scripts/release-ios.sh: your Xcode account, or ASC_KEY_ID / ASC_ISSUER_ID /
# ASC_KEY_PATH for an API key.
#   scripts/release-mac-appstore.sh          # build number = YYYYMMDDHHMM
#   UPLOAD=0 scripts/release-mac-appstore.sh # archive + export only
set -euo pipefail

cd "$(dirname "$0")/.."
TEAM=$(awk '/DEVELOPMENT_TEAM:/ {print $2; exit}' project.yml)
BUILD_NUMBER=${1:-$(date +%Y%m%d%H%M)}
ARCHIVE=build/CountdownulaMac.xcarchive
EXPORT=build/export-mac-appstore

AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
        -authenticationKeyPath "$ASC_KEY_PATH")
fi

xcodegen generate --quiet
rm -rf "$ARCHIVE" "$EXPORT"
mkdir -p build
xcodebuild -project Countdownula.xcodeproj -scheme Countdownula -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} -quiet archive

DESTINATION=upload
[[ "${UPLOAD:-1}" == "0" ]] && DESTINATION=export

cat > build/ExportOptions-mac-appstore.plist <<PLIST
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
  -exportOptionsPlist build/ExportOptions-mac-appstore.plist \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [[ "$DESTINATION" == "upload" ]]; then
  echo "Uploaded Mac build $BUILD_NUMBER. Pick it for the macOS version in App Store Connect once processed."
else
  echo "Exported: $EXPORT (build $BUILD_NUMBER)"
fi
