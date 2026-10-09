#!/bin/bash
# The screensaver spike (phase 5.9): build Count Downcula.saver, try it in Apple's real
# legacyScreenSaver host, and collect what it logged.
#
#   scripts/saver-spike.sh install    build (ad-hoc signed) and copy into ~/Library/Screen Savers,
#                                     and mirror this Mac's countdowns into the host's container
#   scripts/saver-spike.sh logs       what the screensaver logged in the last 30 minutes, and how
#                                     many legacyScreenSaver processes are still running
#   scripts/saver-spike.sh uninstall  remove the screensaver and the mirrored copy
#
# Picking it as your screensaver is yours to do: System Settings > Wallpaper > Screen Saver.
set -euo pipefail
cd "$(dirname "$0")/.."

SAVER="Count Downcula.saver"
INSTALLED="$HOME/Library/Screen Savers/$SAVER"
HOST="$HOME/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/Count Downcula"
GROUP="$HOME/Library/Group Containers/YZ36Z8GSEN.com.countdownula.app/WidgetSnapshot"

case "${1:-}" in
  install)
    xcodegen generate --quiet
    xcodebuild -project Countdownula.xcodeproj -target CountdownculaSaver -configuration Release \
      SYMROOT="$PWD/.build/saver" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= -quiet build
    mkdir -p "$HOME/Library/Screen Savers"
    rm -rf "$INSTALLED"
    cp -R ".build/saver/Release/$SAVER" "$INSTALLED"
    echo "Installed $INSTALLED"
    # What the GitHub build of the app does on every change (SaverSnapshot.mirror), done once by hand
    # so the spike doesn't need that build: copy the widget snapshot into the host's container.
    if [ -d "$GROUP" ]; then
      mkdir -p "$HOST"
      cp "$GROUP"/* "$HOST"/ 2>/dev/null || true
      echo "Mirrored $(ls "$HOST" | wc -l | tr -d ' ') files into the host's container"
    else
      # No app data on this Mac: two demo countdowns, so the read through the sandbox is still tested.
      mkdir -p "$HOST"
      python3 - "$HOST/countdowns.json" <<'PY'
import datetime as dt, json, sys, uuid
now = dt.datetime.now(dt.timezone.utc)
iso = lambda d: d.replace(microsecond=0).isoformat().replace("+00:00", "Z")
json.dump([
    {"id": str(uuid.uuid4()).upper(), "title": "New Year's Eve", "details": "", "isPinned": True,
     "targetDate": iso(dt.datetime(now.year + 1, 1, 1, 5, tzinfo=dt.timezone.utc)),
     "createdAt": iso(now - dt.timedelta(days=30)), "style": {"background": {"scene": {"_0": "fireworks"}}, "font": "expanded"}},
    {"id": str(uuid.uuid4()).upper(), "title": "Halloween", "details": "", "isPinned": True,
     "targetDate": iso(dt.datetime(now.year, 10, 31, 4, tzinfo=dt.timezone.utc)),
     "createdAt": iso(now - dt.timedelta(days=30))},
], open(sys.argv[1], "w"))
PY
      echo "No app data on this Mac; wrote two demo countdowns into the host's container."
    fi
    echo "Now pick it in System Settings > Wallpaper > Screen Saver, preview it, then run: $0 logs"
    ;;
  logs)
    /usr/bin/log show --last 30m --info --predicate 'subsystem == "com.countdowncula.saver"' --style compact
    echo
    echo "legacyScreenSaver processes now: $(pgrep -f legacyScreenSaver | wc -l | tr -d ' ')"
    ps -o pid,%cpu,etime,command -p "$(pgrep -d, -f legacyScreenSaver || echo 0)" 2>/dev/null || true
    ;;
  uninstall)
    rm -rf "$INSTALLED" "$HOST"
    echo "Removed the screensaver and its copy of the countdowns."
    ;;
  *)
    sed -n '2,12p' "$0"
    exit 1
    ;;
esac
