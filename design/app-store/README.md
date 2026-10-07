# App Store screenshots

Upload these on the app's version page in App Store Connect, under **Previews and Screenshots**, in file-name order.

| Folder | Device slot | Size | Screens |
|---|---|---|---|
| `iphone/` | iPhone 6.9" Display | 1320 × 2868 | List, countdown detail, count-up, appearance editor |
| `ipad/` | iPad 13" Display | 2064 × 2752 | List, countdown detail |
| `watch/` | Apple Watch | 416 × 496 | Watch face with complications, list, detail |

App Store Connect scales the 6.9" and 13" sets down for smaller iPhones and iPads, so these are the only sizes needed.

## Retaking them

The iPhone and iPad shots come from the iOS Simulator with the debug demo data:

1. Build the `CountdownulaiOS` scheme (Debug) for an iPhone 17 Pro Max or iPad Pro 13-inch simulator.
2. `xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100`
3. Launch with `-seedDemo -localOnly`, then `xcrun simctl io booted screenshot <file>.png`.

To open a specific countdown, use its link: `xcrun simctl openurl booted countdownula://countdown/<uuid>`. The UUIDs are in `ZCOUNTDOWNRECORD` in the app's `Library/Application Support/Countdownula.store`.

The watch shots come from an Apple Watch Series 11 (46mm) simulator running the `CountdownulaWatch` scheme with `-seedDemo -localOnly`. The watch-face shot was taken on a real watch and is shared with `docs/screenshots/watch-face.png`.

Not included yet: a Lock Screen Live Activity and Home Screen widgets. The simulator's lock screen shows a placeholder date and hides seconds, so take those on a real iPhone.
