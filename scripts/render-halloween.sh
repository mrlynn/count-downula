#!/usr/bin/env bash
# Renders the Halloween marketing images in design/halloween/ to PNG with headless Chrome.
# The day count in square/story is computed at render time, so re-run it to refresh.
# Run from the repo root: scripts/render-halloween.sh
set -euo pipefail
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
dir="$(pwd)/design/halloween"
mkdir -p "$dir/out"

shot() { # page width height output [extra flags]
  "$chrome" --headless --disable-gpu --hide-scrollbars --allow-file-access-from-files \
    --force-device-scale-factor="${5:-1}" ${6:-} --virtual-time-budget=2000 \
    --window-size="$2,$3" --screenshot="$dir/out/$4" "file://$dir/$1" 2>/dev/null
  echo "design/halloween/out/$4"
}

shot og.html 1200 630 og-halloween.png
shot square.html 1080 1080 square-halloween.png
shot story.html 1080 1920 story-halloween.png
shot wordmark.html 1600 1000 wordmark-options.png

# the character alone on a transparent background, at 2x
printf '<html><body style="margin:0;background:transparent"><img src="count.svg" width="800" height="1000"></body></html>' > "$dir/.count-only.html"
shot .count-only.html 800 1000 count.png 2 --default-background-color=00000000
rm "$dir/.count-only.html"
