# App Store screenshots

Upload these on the app's version page in App Store Connect, under **Previews and Screenshots**, in file-name order.

| Folder | Device slot | Size | Screens |
|---|---|---|---|
| `iphone-6.3/` | iPhone with Dynamic Island (medium display) | 1206 × 2622 | List, countdown detail, date pool, the Crypt, appearance editor (occasion scenes), count-up |
| `iphone/` | iPhone 6.9" (if App Store Connect asks for it) | 1320 × 2868 | The same six, at full size |
| `ipad/` | iPad 13" Display | 2064 × 2752 | List, countdown detail, the Crypt |
| `watch/` | Apple Watch | 416 × 496 | Watch face with complications, list, detail |
| `iap-review-paywall.png` | In-app purchase → Review Information → Screenshot | 1206 × 2622 | The Count Downcula Unlimited paywall (for Apple's reviewer only) |

Each slot lists the sizes it accepts under its drop area; check there first. The 6.3" set is the 6.9" set scaled down (`sips -z 2622 1206`); the two screens have the same shape to within 0.1%.

## Retaking them

The iPhone and iPad shots come from the iOS Simulator with the debug demo data:

1. Build the `CountdownulaiOS` scheme (Debug) for an iPhone 17 Pro Max or iPad Pro 13-inch simulator.
2. `xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100`
3. Launch with `-seedDemo -localOnly`, then `xcrun simctl io booted screenshot <file>.png`.

The date pool and the Crypt need a server. Run one locally (`server/`, `npx next dev --port 4319` against a local MongoDB), seed the Crypt with `scripts/seed-crypt.mjs`, and add `-linkServer http://localhost:4319` to the launch arguments. The demo's "Baby Chen Arrives" has a date pool: share its live link from the detail screen, add a few guesses with `POST /api/countdowns/<slug>/pool/guesses`, then guess from the app so one row reads "(you)".

To open a specific countdown, use its link: `xcrun simctl openurl booted countdownula://countdown/<uuid>`. The UUIDs are in `ZCOUNTDOWNRECORD` in the app's `Library/Application Support/Countdownula.store`.

The watch shots come from an Apple Watch Series 11 (46mm) simulator running the `CountdownulaWatch` scheme with `-seedDemo -localOnly`. The watch-face shot was taken on a real watch and is shared with `docs/screenshots/watch-face.png`.

Not included yet: a Lock Screen Live Activity and Home Screen widgets. The simulator's lock screen shows a placeholder date and hides seconds, so take those on a real iPhone.
