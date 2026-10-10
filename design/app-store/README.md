# App Store screenshots

Upload these on the app's version page in App Store Connect, under **Previews and Screenshots**, in file-name order.

| Folder | Device slot | Size | Screens |
|---|---|---|---|
| `iphone-6.3/` | iPhone with Dynamic Island (medium display) | 1206 × 2622 | List (with sleeps, workdays and weeks), countdown detail, date pool, the Crypt, appearance editor (occasion scenes), count-up, a birthday in sleeps, a date in Tokyo time, From Calendar |
| `iphone/` | iPhone 6.9" (if App Store Connect asks for it) | 1320 × 2868 | The same nine, at full size |
| `ipad/` | iPad 13" Display | 2064 × 2752 | List, countdown detail, the Crypt, a date in Tokyo time |
| `appletv/` | Apple TV | 1920 × 1080 | Home, a countdown full screen, the Crypt |
| `mac/` | Mac | 1440 × 900 | Menu bar list and detail, editor, free tier and Unlimited |
| `watch/` | Apple Watch | 416 × 496 | Watch face with complications, list, detail |
| `iap-review-paywall.png` | In-app purchase → Review Information → Screenshot | 1206 × 2622 | The Count Downcula Unlimited paywall (for Apple's reviewer only) |

Each slot lists the sizes it accepts under its drop area; check there first. The 6.3" set is the 6.9" set scaled down (`sips -z 2622 1206`); the two screens have the same shape to within 0.1%.

## Retaking them

The iPhone and iPad shots come from the iOS Simulator with the debug demo data:

1. Build the `CountdownulaiOS` scheme (Debug) for an iPhone 17 Pro Max or iPad Pro 13-inch simulator.
2. `xcrun simctl status_bar booted override --time 9:41 --dataNetwork wifi --wifiBars 3 --cellularBars 4 --batteryState charged --batteryLevel 100`
3. Launch with `-seedDemo -localOnly -unlocked`, then `xcrun simctl io booted screenshot <file>.png`. `-unlocked` (debug builds only) hides the free tier's notes; `-openImport calendar` opens From Calendar (grant access first with `xcrun simctl privacy booted grant calendar com.countdownula.app`).

The date pool and the Crypt need a server. Run one locally (`server/`, `npx next dev --port 4319` against a local MongoDB), seed the Crypt with `scripts/seed-crypt.mjs`, and add `-linkServer http://localhost:4319` to the launch arguments. The demo's "Baby Chen Arrives" has a date pool: share its live link from the detail screen, add a few guesses with `POST /api/countdowns/<slug>/pool/guesses`, then guess from the app so one row reads "(you)".

To open a specific countdown, use its link: `xcrun simctl openurl booted countdownula://countdown/<uuid>`. The UUIDs are in `ZCOUNTDOWNRECORD` in the app's `Library/Application Support/Countdownula.store`.

The Mac shots are the Debug build's own windows, captured with `screencapture -l <window id>` and placed on the Mountains scene rendered at 1440 × 900. Launch arguments: `-localOnly` plus `-openPopover` (add `-select "Sonoma Wine Weekend"` for the detail), `-openEditor "Sam's 30th Birthday"`, or `-freeTier -openPaywall` / `-freeTier -openPopover`. The sandboxed app keeps its data in `~/Library/Containers/com.countdownula.app`; move that store aside (and back afterwards) so `-seedDemo` seeds.

The watch shots come from an Apple Watch Series 11 (46mm) simulator running the `CountdownulaWatch` scheme with `-seedDemo -localOnly`. The watch-face shot was taken on a real watch and is shared with `docs/screenshots/watch-face.png`.

The Apple TV shots come from an Apple TV 4K (at 1080p) simulator running the `CountdownculaTV` scheme with `-localOnly -seedDemo`; `-present` opens Next Up full screen and `-crypt` opens the Crypt.

Not included yet: Mac shots of Present and From Calendar (the Debug Mac app shares the installed app's data, so take them with the store moved aside, as above), a Lock Screen Live Activity and Home Screen widgets. The simulator's lock screen shows a placeholder date and hides seconds, so take those on a real iPhone.
