# Count Downcula

<img src="design/app-icon.png" width="128" alt="Count Downcula icon: a blood-red timer ring with fangs">

Native countdowns for vacations, launches, birthdays, or a quick timer: a macOS menu bar app, an iPhone app with widgets and Live Activities, and an Apple Watch app with complications.

The app shows up as **Count Downcula** everywhere you see it. The project, targets, files, bundle IDs and iCloud container keep the original one-word name, `Countdownula`, from when the app was called Count Downula (renamed in October 2026).

[![Download the latest release](https://img.shields.io/github/v/release/mrlynn/count-downula?label=Download&color=c3112d&logo=apple)](https://github.com/mrlynn/count-downula/releases/latest)

<img src="docs/screenshots/menubar.png" width="456" alt="Pinned countdowns in the macOS menu bar">

<p>
  <img src="docs/screenshots/popover.png" width="380" alt="Countdown list in the menu bar popover">
  <img src="docs/screenshots/detail.png" width="380" alt="Countdown detail view with photo and days, hours, minutes, seconds">
</p>

- Click the fanged timer in the menu bar to see **Upcoming** and **Past** countdowns.
- Each countdown has a **title**, **description**, **photo**, and either a target **date & time**, a **timer** duration, or a **start date to count up from** (time since quitting smoking, getting sober, meeting someone).
- **Milestones** mark the moments along the way ("Halfway there", "1 week to go", "90 days"), each with its own notification and, on iPhone, a burst of confetti.
- **Pin** any countdown and it gets its own live menu bar item (photo thumbnail + title + time left). Click it to jump straight to its details.
- A notification fires when a countdown finishes.
- **iCloud sync** keeps countdowns and photos in step between your Mac, iPhone and Apple Watch.

## iPhone

<p>
  <img src="docs/screenshots/iphone-app.jpg" width="240" alt="Count Downcula iPhone app with a pinned countdown as a full-bleed photo card above the upcoming list">
  <img src="docs/screenshots/iphone-lock.jpg" width="240" alt="Lock Screen with a countdown Live Activity and Count Downcula widgets">
  <img src="docs/screenshots/iphone-home.jpg" width="240" alt="Home Screen with Up Next and photo countdown widgets, and a timer in the Dynamic Island">
</p>

The iPhone (and iPad) app lists your countdowns with the next one up as a full-bleed card, shows a live days/hours/minutes/seconds view, and lets you add or edit countdowns with a photo from your library. The **+** button also offers one-tap quick timers. It schedules its own alerts and syncs with the Mac and watch through iCloud.

- **Appearance:** give each countdown its own background (your photo, one of 12 built-in scenes, a gradient or a color), font and colors. Widgets, the watch and the Mac use it too.
- **Count up:** track the time since something began, with standard milestones (24 hours, 1 week, 30/60/90 days, 6 months, every year), money saved per day, and a gentle **Reset** that keeps your history and best run. Templates for Sober, Smoke-Free, Together and New Job.
- **Repeats every year:** birthdays and anniversaries roll over to next year once the day has passed.
- **Share as image:** a 1080 × 1350 card of any countdown for Messages or Instagram.
- **Pricing:** free for up to 3 active countdowns (timers and count-ups count, finished ones don't). **Count Downcula Unlimited** is a one-time $2.99 in-app purchase that removes the limit on iPhone, iPad and Apple Watch. The Mac app, distributed directly, is always unlocked (`DIRECT_DISTRIBUTION`).

| Where | What |
|---|---|
| Home Screen | **Countdown** widget (small, medium, large) with the photo behind the time left, and an **Up Next** list (medium, large) |
| StandBy | The small Countdown widget, drawn to read on black |
| Lock Screen | Circular, rectangular and inline widgets, the same designs as the watch complications |
| Live Activity | Lock Screen banner and Dynamic Island with a live timer and progress ring |

The Countdown widget follows **Next Up** (soonest pinned, otherwise soonest) or a countdown you pick. Tapping any widget or Live Activity opens that countdown.

**Pin** is the iPhone's version of the Mac's menu bar item: a pinned countdown is featured in widgets and goes live on the Lock Screen and in the Dynamic Island once it's in its final 8 hours (iOS ends Live Activities after 8 hours). New timers go live straight away, and any countdown in that window can be put on the Lock Screen from its detail screen.

## Apple Watch

<p>
  <img src="docs/screenshots/watch-face.png" width="208" alt="Infograph watch face with Count Downcula corner and circular complications">
  <img src="docs/screenshots/watch-app.png" width="208" alt="Count Downcula watch app listing countdowns">
</p>

The watch app ships inside the iPhone app and runs on its own once installed (it doesn't need the phone nearby). It lists your countdowns, shows a live days/hours/minutes/seconds view, and lets you start a quick timer or add a date right from your wrist. Countdowns sync with the Mac and iPhone through iCloud, and the watch schedules its own alerts.

**Complications** (WidgetKit) work on any face that has slots:

| Slot | Shows |
|---|---|
| Circular | The fanged ring drains as the date gets closer, with days (or hours, or a live timer) in the middle |
| Rectangular | Title, live time left and a progress bar; adds the photo on full-color faces and in the Smart Stack |
| Corner | Short time left with a curved gauge and the title |
| Inline | `Sonoma · 15d 23h` along the top of the face |

Each complication can follow **Next Up** (your soonest pinned countdown, otherwise the soonest one) or a specific countdown.

Apple doesn't allow third-party watch faces. To share a "Count Downcula face", set one up (Infograph or Modular work well, in a red color), then long-press it and choose **Share**. That creates a `.watchface` file anyone with the app can add in one tap.

## Download

Grab **Countdownula-x.y.z.zip** from the [latest release](https://github.com/mrlynn/count-downula/releases/latest), unzip it, and drag **Countdownula.app** to `/Applications`.
It's a universal app (Apple Silicon + Intel) and needs macOS 14 Sonoma or later. Finder shows it as Count Downcula.

Releases from 1.1 on are signed with Developer ID and notarized by Apple, so the first launch only asks you to confirm opening an app downloaded from the internet.

## Build from source

Requires Xcode 16+ (macOS 14 / iOS 17 / watchOS 10 deployment targets), [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`), and an Apple Developer account. iCloud needs real signing. The project is defined in `project.yml`; the `.xcodeproj` is generated and not committed.

```bash
./scripts/build-app.sh          # signed Mac build → build/Countdownula.app
open build/Countdownula.app
```

Debug Mac builds take optional launch arguments for screenshots: `-seedDemo` (sample countdowns, using macOS wallpapers as photos), `-openPopover` (opens the list at launch) and `-localOnly` (no iCloud). To keep them away from your real countdowns, build with `scripts/build-app.sh debug` and point the app at a scratch home folder:

```bash
CFFIXED_USER_HOME=/tmp/cd-demo .build/xcode/Build/Products/Debug/Countdownula.app/Contents/MacOS/Countdownula -localOnly -seedDemo -openPopover
```

To use your own team, change `DEVELOPMENT_TEAM` and the `com.countdownula.*` / `iCloud.com.countdownula.app` / `group.com.countdownula.app` identifiers in `project.yml` and `Sources/Shared/SharedConfig.swift`.

**iPhone app:** run `xcodegen generate`, open `Countdownula.xcodeproj`, pick the **CountdownulaiOS** scheme and your iPhone or a simulator, and click Run. The scheme has optional `-seedDemo` (sample data) and `-localOnly` (no iCloud) launch arguments. It shares the Mac app's bundle ID (`com.countdownula.app`) so the two can share an App Store record; the widget extension is `com.countdownula.app.widgets`.

**Changing the synced model:** CloudKit only accepts new `CountdownRecord` fields in Production after they exist in the Development schema and are deployed. Run a debug iPhone build, signed and signed into iCloud on the device or simulator, with the `-initializeCloudKitSchema` launch argument. It writes every field to Development using a throwaway store, without touching your countdowns. Check the result with `xcrun cktool export-schema --team-id YZ36Z8GSEN --container-id iCloud.com.countdownula.app --environment development`, then use **Deploy Schema Changes…** in the CloudKit Console. Production deploys can't be undone.

**Watch app:** run `xcodegen generate`, open `Countdownula.xcodeproj`, pick the **CountdownulaWatch** scheme and your watch, and click Run. Xcode registers the watch with your developer account the first time. In the simulator, the scheme has optional launch arguments: `-seedDemo` (sample data), `-complicationGallery` (renders every complication size), and `-localOnly` (no iCloud).

**Release:** `NOTARY_PROFILE=countdownula scripts/release-mac.sh` archives, exports with Developer ID, notarizes, staples and zips the app. The `countdownula` profile is a notarytool keychain profile; the script header shows how to create one. Before the first public release, open the [CloudKit Console](https://icloud.developer.apple.com/), select `iCloud.com.countdownula.app`, and **Deploy Schema Changes** to Production. Release builds sync through the Production environment.

**TestFlight / App Store (iPhone, iPad and Watch):** create the app in App Store Connect with bundle ID `com.countdownula.app`, sign in to your Apple ID in Xcode → Settings → Accounts, then run `scripts/release-ios.sh`. It archives the iPhone app (with the watch app and both widget extensions embedded), signs it for the App Store and uploads it. The build shows up under TestFlight after processing. Each upload needs a new build number: the script uses a timestamp, or pass one (`scripts/release-ios.sh 3`). `UPLOAD=0` exports the `.ipa` without uploading, and `ASC_KEY_ID` / `ASC_ISSUER_ID` / `ASC_KEY_PATH` switch to App Store Connect API key auth for CI.

## Logo

The mark is a countdown timer whose lower jaw bares two fangs. Sources live in `design/`:

| File | Use |
|---|---|
| `app-icon.svg` | Full-color app icon (blood-red ring, bone fangs and hand, midnight squircle) |
| `mark.svg` | Monochrome mark for docs and marketing |
| `mark-menubar.svg` | Menu bar variant: tighter crop and bigger fangs so it reads at 18pt |
| `app-icon-watch.svg` | Full-bleed watch icon (watchOS masks it to a circle) |

After editing an SVG, regenerate `Resources/AppIcon.icns`, the watch icon and the menu bar PNGs:

```bash
swift scripts/render-icons.swift
```

## Data

Countdowns live in a SwiftData store (`~/Library/Application Support/Countdownula/Countdownula.store` on the Mac) that syncs through your **private** iCloud database. Photos are stored as a 1400px JPEG plus a 240px thumbnail. Version 1.0's `countdowns.json` is imported automatically on first launch and renamed to `countdowns.imported.json`.

## Layout

| Path | Purpose |
|---|---|
| `Sources/Shared/` | `Countdown` model and formatting, SwiftData `CountdownRecord`, `CountdownRepository` (CRUD + CloudKit), `WidgetSnapshot` (App Group hand-off to complications), `FangMark` (the logo drawn in SwiftUI, doubling as a progress dial) |
| `Sources/Countdownula/` | Mac app: status items and popover (`AppDelegate`), `CountdownStore`, popover and editor views |
| `Sources/CountdownulaiOS/` | iPhone and iPad app: `PhoneStore` (sync, snapshot, alerts), `LiveActivities`, list, detail and editor views |
| `Sources/CountdownulaiOSWidgets/` | iPhone widget extension: Home Screen and StandBy widgets, Up Next list, Live Activity and Dynamic Island |
| `Sources/PhoneShared/` | Shared by the iPhone app and its widgets: Live Activity attributes, deep links, image downsampling |
| `Sources/CountdownulaWatch/` | Watch app: `WatchStore` (sync, snapshot, alerts), list, detail and add views, debug complication gallery |
| `Sources/CountdownulaWidgets/` | Configuration intent, timeline provider and accessory views shared by the watch complications and iPhone Lock Screen widgets |
