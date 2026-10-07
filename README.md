# Countdownula

<img src="design/app-icon.png" width="128" alt="Countdownula icon: a blood-red timer ring with fangs">

A native macOS menu bar app for countdowns: vacations, launches, birthdays, or a quick timer.

[![Download the latest release](https://img.shields.io/github/v/release/mrlynn/count-downula?label=Download&color=c3112d&logo=apple)](https://github.com/mrlynn/count-downula/releases/latest)

<img src="docs/screenshots/menubar.png" width="456" alt="Pinned countdowns in the macOS menu bar">

<p>
  <img src="docs/screenshots/popover.png" width="380" alt="Countdown list in the menu bar popover">
  <img src="docs/screenshots/detail.png" width="380" alt="Countdown detail view with photo and days, hours, minutes, seconds">
</p>

- Click the fanged timer in the menu bar to see **Upcoming** and **Past** countdowns.
- Each countdown has a **title**, **description**, **photo**, and either a target **date & time** or a **timer** duration.
- **Pin** any countdown and it gets its own live menu bar item (photo thumbnail + title + time left). Click it to jump straight to its details.
- A notification fires when a countdown finishes.

## Download

Grab **Countdownula-x.y.z.zip** from the [latest release](https://github.com/mrlynn/count-downula/releases/latest), unzip it, and drag **Countdownula.app** to `/Applications`.
It's a universal app (Apple Silicon + Intel) and needs macOS 14 Sonoma or later.

The app isn't notarized, so macOS blocks the first launch. **Right-click the app → Open → Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Countdownula.app
```

## Build from source

Requires macOS 14+ and Xcode (Swift 6 toolchain).

```bash
./scripts/build-app.sh          # release build → build/Countdownula.app
open build/Countdownula.app
```

Copy `build/Countdownula.app` to `/Applications` to keep it around.

## Logo

The mark is a countdown timer whose lower jaw bares two fangs. Sources live in `design/`:

| File | Use |
|---|---|
| `app-icon.svg` | Full-color app icon (blood-red ring, bone fangs and hand, midnight squircle) |
| `mark.svg` | Monochrome mark for docs and marketing |
| `mark-menubar.svg` | Menu bar variant: tighter crop and bigger fangs so it reads at 18pt |

After editing an SVG, regenerate `Resources/AppIcon.icns` and the menu bar PNGs:

```bash
swift scripts/render-icons.swift
```

## Data

Stored in `~/Library/Application Support/Countdownula/`: `countdowns.json` plus an `images/` folder.
Imported photos are downscaled to 1400px JPEGs.

## Layout

| File | Purpose |
|---|---|
| `AppDelegate.swift` | Status items (main + one per pinned countdown), popover, editor window |
| `CountdownStore.swift` | Observable model, JSON persistence, 1s tick, completion notifications |
| `Countdown.swift` | Model and time formatting |
| `PopoverView.swift` / `CountdownRow.swift` / `DetailView.swift` | Popover UI |
| `EditorView.swift` | Create/edit form with photo picker and drag-and-drop |
