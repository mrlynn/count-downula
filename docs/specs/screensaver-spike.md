# Screensaver spike (phase 5.9)

October 9, 2026. The plan's three questions about a Count Downcula screensaver, and a working prototype to settle them: `Count Downcula.saver` (target `CountdownculaSaver`). It shows pinned countdowns full screen in their styles, rotating every 30 seconds. With nothing pinned it shows Next Up, and a countdown in its last minute keeps the screen. The layout is the shared `PresentView`, so it matches Present on the Mac and the web.

## 1. Data: how the screensaver gets the countdowns

Third-party screensavers run inside Apple's `legacyScreenSaver` host, sandboxed to that host's container. Inside it, the saver's Application Support is `~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support`. It can't use the app's SwiftData store or the App Group the widgets read.

**Decision: a snapshot the GitHub build writes into the host's container.** The GitHub build isn't sandboxed (`Resources/CountdownulaDirect.entitlements`), so it can write there.
- On every change it already writes the widget snapshot (countdowns, thumbnails, photos). `SaverSnapshot.mirror()` now copies that folder into `.../Application Support/Count Downcula/`, changing only what changed.
- It does nothing until the host's container exists, so a Mac that has never run a third-party screensaver gets no stray folder.
- The screensaver reads the copy with `WidgetSnapshot`, pointed at its own Application Support.

Why not the server: the saver would only see countdowns that have a live link, it would need the network at every start, and photos would be the web's backdrops rather than the originals. The snapshot shows everything, offline. Server fetches stay a fallback if a future macOS closes the container to outside writers.

The Mac App Store build is sandboxed and can't write into another app's container. That fits the distribution answer below.

## 2. Distribution

The Mac App Store doesn't distribute screensavers. The plan is unchanged:
- Ship `Count Downcula.saver` inside the GitHub direct build, and as a download from countdowncula.com.
- People install it by double-clicking.
- It needs to be signed with the Developer ID and notarized alongside the app. `scripts/release-mac.sh` doesn't do this yet.

Note that on macOS 26 the screensaver picker is a fixed-size sheet inside System Settings > Wallpaper, and third-party screensavers there have been reported missing from the list in early betas.

## 3. The legacyScreenSaver host on Sonoma and later

Known problems, from developers who ship screensavers (Aerial's ScreenSaverMinimal template, iScreensaver, Wade Tregaskis via Michael Tsai, Apple's developer forums):

| Problem | Since | What the prototype does |
|---|---|---|
| `stopAnimation` is never called outside the System Settings preview | Sonoma | Doesn't rely on it. On `com.apple.screensaver.willstop` it exits the host after 2 seconds, the ScreenSaverMinimal workaround (heavy-handed, but the only one known). Never in a preview. |
| A new view every start while old ones keep running, piling up and using CPU | Sonoma | Each new instance retires older ones on the same screen size. |
| The host process is never terminated, and can be left at 100% CPU | Sonoma | The same exit on willstop. |
| `animateOneFrame` timing is unreliable | Sonoma | Unused: SwiftUI's `TimelineView` draws. |
| `isPreview` is wrong in some cases, with no known workaround | Tahoe 26 | Only used to skip the exit. A wrong value leaves an extra host process running, the same as today's bug. |
| Multiple monitors broken in new ways | Tahoe 26 | Untested; one instance per screen size is the most that can be done. |
| WKWebView content disappears after 3 seconds | Tahoe 26.4 | Not affected: no web views. |

## What was tested

- Unit tests (`SaverSnapshotTests`): rotation order, Next Up fallback, the last-minute hold, the mirror copying changes and removing what's gone, waiting for the host's container, and the export path.
- The bundle builds (ad-hoc and Release) with principal class `CountdownculaSaver.CountdownculaSaverView`.
- Loaded in a throwaway test app outside the host, with a demo snapshot, it rendered the countdown in its last minute from the mirrored copy and logged its probes. That run wasn't sandboxed, so its file and network results don't count.
- The GitHub build of the Mac app, the iPhone app and the watch app build with the change.

## Tested in the real host (macOS 26.6, one 3440 × 1440 display)

Run on October 9, 2026 with `scripts/saver-spike.sh`, and read from the screensaver's own log lines:

| Question | Result |
|---|---|
| Reads the snapshot mirrored into the host's container | **Yes**, in every run (the demo snapshot, 438 bytes) |
| Reads the App Group directly | **No**, as expected, so the mirror is needed |
| Reaches the server | **Yes** (HTTP 200), so server fetches are a viable fallback |
| A real start (Hot Corner) | Correct `isPreview` (false), full display size, and it draws |
| Dismissing a real start | `willstop` arrives within seconds, and leaving the host leaves no process running |
| Starting again after the host has exited | Works: macOS starts a fresh host, and the countdown shows every time |
| System Settings' small preview | Gets proper `stopAnimation` calls |
| The full-screen **Preview** button | **Leaks:** no stop and no `willstop`, so the copy kept drawing at about 5% CPU minutes after it was dismissed |

For the Preview leak, there's now a backstop: once the window has been off screen for 10 seconds, the saver stops drawing and leaves the host. It hasn't been seen to fire yet, so check it on the next round of testing, along with a second monitor.

`scripts/saver-spike.sh logs` collects the log again, and `scripts/saver-spike.sh uninstall` removes the screensaver.

## Recommendation

**Go, for the GitHub build.** The mirrored snapshot works in the real host, real starts and stops behave with the workaround, and the prototype is most of the feature. The server is a tested fallback if a future macOS closes the container.

Remaining work after a go:
- Developer ID signing and notarization for the `.saver`, and bundling it in the release DMG.
- A download page.
- A "Show in screensaver" choice in the Mac app (pinned is the rule today).
- Checking the Preview backstop, and a test on a second monitor.
- Removing the spike probes (`SaverSpike`) before release.
