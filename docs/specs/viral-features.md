# Count Downcula viral features spec

Status: draft, October 8, 2026
Owner: Michael Lynn

## Why this exists

Count Downcula does a lot for one person. Milestones, count-ups, Live Activities, complications, styles and a share card all work well on your own devices. None of it reaches anyone else except as a static JPEG. Your sync runs through a private iCloud database, so a countdown can never appear on a friend's phone.

Each feature in this spec closes that gap. The goal is a loop where every countdown you care about pulls other people in, and every one of them can start their own.

The north star metric is shared countdowns per active user per month. Supporting metrics are link opens, App Clip launches, App Clip to full install conversion, and the share of new installs that came from a link.

## Architecture decision: add a small server

SwiftData's CloudKit integration only supports the private database. It can't create a CKShare or read a shared zone. Building sharing on raw CloudKit would mean a second persistence layer beside SwiftData, and it still wouldn't give you public web links, live preview images, App Clip data for people without iCloud access to the share, or push-to-start Live Activities.

So the plan adds one service, the Count Downcula server:

| Piece | Choice | Why |
|---|---|---|
| Framework | Next.js (App Router) in `server/` | API routes, server-rendered share pages and `next/og` image rendering in one deploy |
| UI | Material UI | Matches the house stack |
| Data | MongoDB Atlas | Flexible documents fit the countdown JSON the app already writes (style, milestones, extras) |
| Hosting | Vercel project `countdowncula-server` | The marketing site already deploys there |
| Domain | `go.countdowncula.com` | Keeps the static site and its strict CSP untouched, and gives the App Clip a clean associated domain |

Private countdowns keep syncing through iCloud exactly as they do today. The server only ever sees a countdown you choose to publish or share.

### Identity

Version one uses no accounts. When you publish a countdown, the server returns a `slug` and a random `ownerToken`. The app stores the token in the iCloud Keychain, keyed by the countdown's UUID, so all your devices can edit or unpublish it. The server stores only a SHA-256 hash of the token.

The slug and URL ride along in `CountdownExtras` as a new optional `link` field. Extras sync as a JSON blob, so this needs no CloudKit schema change.

Sign in with Apple comes later, when shared countdowns need a stable member identity (phase 2).

### Data model

`countdowns` collection:

| Field | Type | Notes |
|---|---|---|
| `slug` | string, unique | 8 characters, URL safe, no ambiguous letters |
| `ownerTokenHash` | string | SHA-256 of the owner token |
| `title`, `details` | string | Title capped at 120 characters, details at 1,000 |
| `targetDate` | date | |
| `kind` | `event`, `timer`, `countUp` | |
| `createdAt`, `updatedAt` | date | |
| `style` | object | The app's `CountdownStyle` JSON, stored as is |
| `milestones` | array | The app's `Milestone` JSON |
| `hasPhoto` | bool | Photo bytes live in `photos` |
| `visibility` | `link`, `public` | `public` makes it eligible for the crypt feed |
| `stats` | object | `views`, `clipLaunches`, `subscribers` |

`photos` collection: `{ slug, jpeg: BinData, width, height }`, one 1080px JPEG per countdown, capped at 400 KB.

## The features

Each feature lists what it is, why it spreads, how it works, what it depends on, and a rough size (S is days, M is a week or two, L is several weeks).

### 1. Live link previews (phase 1, size M)

What it is: every countdown can get a public URL, like `go.countdowncula.com/c/k7Pq2mXa`. The page shows the countdown ticking live, styled like the app. The link preview image renders on request, so pasting the link in iMessage, Slack or X shows today's number.

Why it spreads: a link preview that changes day to day gets noticed, and it rewards reposting. Every view of the page carries a download button.

How it works: the app posts the countdown and photo to `POST /api/countdowns`. The page at `/c/[slug]` renders on the server with a client component for the ticking clock. `/c/[slug]/opengraph-image` uses `ImageResponse` and sends `Cache-Control: public, s-maxage=3600, stale-while-revalidate=600`, so previews refresh within the hour. iMessage caches previews on its own schedule, so the image also bakes the number into its URL (`?d=23`) through the page's `og:image` tag, forcing a fresh fetch when the day changes.

App changes: a Share Link button in the countdown detail screen, a published badge, and Unpublish. Edits to a published countdown push to the server.

Depends on: the server, MongoDB Atlas cluster, DNS for `go.countdowncula.com`.

### 2. Shared countdowns, "The Bite" (phase 2, size L)

What it is: you invite people to a countdown. It shows up in their app, widgets, Lock Screen and Dynamic Island with your photo and style, ticking in sync with yours. Edits from the owner reach everyone.

Why it spreads: weddings, trips, launches and parties have 10 to 150 people who care about the same date. Each invite is an install prompt with a personal reason attached.

How it works: a shared countdown is a published countdown plus a `members` list. Joining stores a local `CountdownRecord` with a `remoteSlug` in extras, so every existing surface (widgets, complications, Live Activities, the Mac menu bar) works with no changes. The app refreshes subscribed countdowns on launch, on background app refresh, and on a silent push when the owner edits.

Roles: owner (edit, delete, remove members) and member (view, leave, set personal pin and alerts). Members can't edit the shared fields in version one.

Depends on: feature 1, Sign in with Apple for member identity, APNs key for silent pushes.

Built (version one, October 8, 2026): no accounts. Joining stores a random member key in the iCloud Keychain, used only to leave; the owner sees a count, not names, and can't remove individual members (stopping sharing removes everyone). Members join from a tapped link (universal link on `go.countdowncula.com/c/*`, or `countdownula://join/<slug>` from the page's "Count down with me" button) or by pasting a link into Join Shared Countdown. Copies refresh when the app comes to the front, in background app refresh, and every 15 minutes on the Mac; silent pushes wait for the APNs key. If the owner stops sharing, the member keeps the countdown as their own. Joined countdowns don't count toward the free tier's limit. Sign in with Apple is deferred until member names or per-member removal are needed.

### 3. App Clip (phase 2, size M)

What it is: tapping a countdown link on an iPhone opens a 15 MB App Clip with the live countdown, a "Keep it" button and a Live Activity offer if the date is within 8 hours.

Why it spreads: it removes the install wall from the share loop. The person sees the payoff before deciding to install.

How it works: a new `CountdownulaClip` target in `project.yml`, sharing `Countdown`, `StyleViews`, `Scenes` and `FangMark`. The App Clip experience URL prefix is `https://go.countdowncula.com/c/`. The server serves `/.well-known/apple-app-site-association` with `appclips` and `applinks` entries. Keep it hands off to the full app through the App Group so the countdown is waiting after install.

Depends on: feature 1, an App Clip bundle ID (`com.countdownula.app.Clip`), App Store Connect App Clip experience setup.

Built (October 8, 2026): the `CountdownulaClip` target (about 5 MB) shows the shared countdown live with its member count, Keep It and Share. Keep It leaves the slug in the App Group and opens the App Store overlay; the full app joins it the first time it opens. The server's AASA lists the clip and live pages carry the Safari App Clip card tag. The Live Activity offer is deferred: the clip doesn't include the widget extension that draws Live Activities, so it can't start one yet.

### 4. The sealed coffin (phase 3, size L)

What it is: on a shared countdown, anyone can drop in a note, photo or short video. Contributions stay sealed until zero, then open together with confetti and a reveal sequence.

Why it spreads: it gives people a reason to invite others early and a reason for everyone to come back at zero. A birthday with 30 sealed messages is something people film.

How it works: `contributions` collection `{ slug, authorId, kind, text, mediaKey, createdAt }`. Media goes to object storage (Vercel Blob or S3), not MongoDB. The API refuses to return content before `targetDate`, which is the real lock. Before zero, members see only a count and contributor avatars ("12 sealed"). The owner gets a notification as contributions arrive. Moderation: owner can remove any contribution, and reports go to a review queue.

Depends on: feature 2, object storage, a content policy and report flow before launch.

Built (version one, October 8, 2026): notes (up to 500 characters) and one photo per contribution, signed with a name the person types. Owners and members can add before zero; the server refuses content before zero except to its author. Photos live in a private Vercel Blob store (`countdowncula-coffin`). The owner can remove anything and authors their own; anyone in the countdown can report, which emails a signed review link (Resend, from `onboarding@resend.dev` to `REPORT_TO`) to a confirm-to-remove page. Unpublishing deletes the coffin. Video and owner notifications as contributions arrive are deferred.

### 5. Synchronized zero (phase 3, size M)

What it is: when a shared countdown hits zero, every member's Dynamic Island and Lock Screen hits zero together and fires confetti, even for members who never opened the app that day.

Why it spreads: New Year's Eve, a product launch, or a gender reveal across 50 phones at once is the kind of moment people record.

How it works: push-to-start Live Activities (iOS 17.2 and later). The app registers its push-to-start token with the server for each shared countdown. Eight hours before zero, a Vercel Cron job sends a push-to-start to every member, then an update at zero with the celebration state. The existing `CountdownLiveActivity` gains an `ended` content state that runs the confetti.

Depends on: feature 2, APNs auth key, Vercel Cron.

Built (October 8, 2026): each phone in a shared countdown (owner or member) registers its push-to-start token and its own local countdown ID with the server, plus the update token of any Live Activity running for it. A Vercel Cron job (`/api/cron/live`, every minute, `CRON_SECRET`) sends each phone one push-to-start per target date inside the eight hour window, and the celebration (`event: end`, `celebrating: true`, an alert) at zero. Failed sends retry the next minute; nothing is sent or marked until the APNs key is set. The activity shows "It's here! 🎉" in that state; Live Activities can't run particle confetti, so the confetti stays in the app.

### 6. Animated share cards (phase 1, size M)

What it is: Share as Video exports a 6 second loop at 1080 by 1920 where the fang ring drains and the seconds tick, ending on the title and the Count Downcula mark.

Why it spreads: video gets more reach than still images on Stories, Reels and TikTok, and it's a native fit for Stories' vertical format.

How it works: render frames of a SwiftUI view with `ImageRenderer` at 30 fps into `AVAssetWriter`. Reuse `ShareCardView` with a `now` that advances per frame. Offer both the existing still card and the video in the share sheet. Add an Instagram Stories handoff through its pasteboard URL scheme.

Depends on: nothing new.

### 7. Countdowns from a screenshot (phase 4, size M)

What it is: share a flight confirmation, ticket, invite or screenshot to Count Downcula and it fills in the title, date, place and a fitting scene.

Why it spreads: it lowers the cost of creating a countdown, and more countdowns means more shares.

How it works: a Share Extension and an Action Extension. Text comes from Vision OCR for images and from the shared text or PDF otherwise. Apple's on-device Foundation Models framework (iOS 26) extracts a structured `CountdownDraft` with guided generation, with `NSDataDetector` as the fallback on devices without it. The editor opens prefilled for confirmation, never saves silently.

Also in scope: App Intents and App Shortcuts ("How long until Sonoma?", "Start a 10 minute timer", "Add a countdown"), and Spotlight indexing of countdowns.

Depends on: nothing new.

Built (October 8, 2026): a Share Extension ("Count Downcula" in the share sheet) for images, PDFs, text and links. Vision reads images, PDFKit reads PDFs; Foundation Models (iOS 26+) suggests the title and place, and `NSDataDetector` supplies the date, joining a day and a time printed on separate lines, read as wall-clock time. The draft is confirmed in the sheet and handed to the app through the App Group (`DraftHandoff`); the app adds it when it next comes forward, or shows the paywall if the person is at the free limit. App Shortcuts: How Long Until, Start a Timer, Add a Countdown. Countdowns are indexed in Spotlight. The separate Action Extension from the spec isn't needed: the share sheet covers the same inputs.

### 8. Apple Wallet passes (phase 3, size M)

What it is: Add to Wallet turns a countdown into an event ticket style pass with the photo and date. It surfaces on the Lock Screen as the day approaches and can be sent through Messages to people without the app.

Why it spreads: a second path into the loop for people who won't install anything.

How it works: the server signs `.pkpass` bundles with a Pass Type ID certificate (`pass.com.countdownula.app`). `relevantDate` drives Lock Screen relevance. The pass web service endpoints (`/api/wallet/v1/...`) push updates when the owner edits. The pass back links to the countdown page.

Depends on: feature 1, Pass Type ID certificate.

Built (October 8, 2026): an event ticket per shared countdown at `/c/<slug>/pass` (Add to Apple Wallet on the live page and the app's detail screen), with the backdrop as the strip, the date in the owner's time zone, a relative "in 5 days" field Wallet keeps current, `relevantDate`/`relevantDates` for the Lock Screen, an expiry a day after zero, and a QR code back to the live page. The full PassKit web service is in place (`/api/wallet/v1/...`, registrations in `walletRegistrations`) and owner edits push an update to every device holding the pass. Signing waits on `PASS_CERT_PEM`, `PASS_KEY_PEM` and `PASS_WWDR_PEM`; until then the routes answer 503 and the buttons stay hidden on the web.

### 9. The Count speaks (phase 1, size S to M)

What it is: an opt-in personality pack per countdown. Milestone notifications and the finish alert get lines in Count Downcula's voice ("Three nights remain. The anticipation is... delicious."), and the final 10 seconds can play a spoken countdown.

Why it spreads: a notification people screenshot is free marketing, and it gives the brand a voice that plain timer apps don't have.

How it works: a `voice` field in extras (`standard`, `count`). A bundled line library keyed by milestone kind and time left, with several variants each so it doesn't repeat. Spoken lines use pre-recorded audio files (licensed voice actor or a commissioned synthetic voice) shipped as notification sounds under 30 seconds. Seasonal packs (Halloween, New Year) ship as app updates.

The character must stay original. No references, phrasing or catchphrases from existing counting vampires.

Depends on: voice recordings for the spoken part. Text lines need nothing new.

### 10. Sunrise and moon modes (phase 1, size S)

What it is: built-in countdowns to the next sunrise and sunset at your location, framed as vampire safety ("Sunrise in 6h 12m. Get to your coffin."), plus a next full moon countdown.

Why it spreads: it's a joke people get in one glance, and it gives press and social posts an easy hook.

How it works: compute sunrise, sunset and moon phase on device with standard NOAA solar and lunar algorithms. A new `Countdown.Kind` would need care with older builds, so these use `kind: event` plus an `extras.auto` field (`sunrise`, `sunset`, `fullMoon`) that tells the store to roll the target forward after each one passes, the same way yearly repeat works today. Location is requested only when you add one, and only city precision is used.

Depends on: nothing new.

### 11. The public crypt (phase 4, size M)

What it is: a browsable feed of countdowns people care about, such as game releases, Apple events, eclipses, playoff games, album drops and Halloween. One tap subscribes, and it behaves like a shared countdown you don't own.

Why it spreads: each entry has a public page that can rank in search, and fans share the pages on their own.

How it works: countdowns with `visibility: public` and a `curated` flag. A staff curated list at launch, then user submissions with review. Pages at `go.countdowncula.com/crypt` and `/crypt/[category]`. Subscriber counts show on each entry.

Depends on: features 1 and 2.

Built (version one, October 8, 2026): a curated list only, no user submissions yet. Entries come from `server/crypt/launch.json` (the approved list is in `docs/specs/crypt-launch-list.md`) and are upserted by slug through `PUT /api/admin/crypt` with `CRYPT_ADMIN_TOKEN` (`node scripts/seed-crypt.mjs`). Holidays use **floating local times**: the server stores `floating: "2027-01-01T00:00:00"`, and the browser and the app each read it on their own clock, so New Year hits zero at local midnight everywhere. Astronomical events are one exact UTC moment. Pages at `/crypt` and `/crypt/[category]` (holidays, sky, sports, fun), with scene backdrops pre-rendered from the app's `SceneArt` into `server/public/scenes`. Public entries are indexable; link-only ones stay `noindex`. In the app, Browse the Crypt in the + menu joins an entry like any shared countdown. Public countdowns have no coffin, and floating ones skip the synchronized zero push, since zero isn't one moment. Entries drop off a day after zero; rolling holidays to next year is a manual reseed for now.

### 12. Date pools (phase 4, size S to M)

What it is: friends guess when something will happen, like the baby's arrival, a ship date or the first snow. When the real date gets set, the countdown fills in and the closest guess wins bragging rights.

Why it spreads: guessing gets everyone to commit, and the result gives everyone a reason to come back.

How it works: a shared countdown with `kind: pool`, a guesses array, and a close action for the owner that sets the date. No money, entry fees or prizes, to stay clear of gambling rules.

Depends on: feature 2.

## Phases

| Phase | Ships | Needs from you |
|---|---|---|
| 1. Foundation and quick wins | Server, live link previews (1), animated cards (6), voice text lines (9), sunrise and moon (10) | MongoDB Atlas connection string, Vercel project, DNS record for `go.countdowncula.com` |
| 2. Sharing | Shared countdowns (2), App Clip (3), Sign in with Apple | App Clip bundle ID and experience, APNs key |
| 3. Moments | Sealed coffin (4), synchronized zero (5), Wallet passes (8) | Object storage, Pass Type ID certificate, content policy |
| 4. Growth | Screenshot import and App Intents (7), public crypt (11), date pools (12) | Curated launch list |

The Halloween test: phase 1 ships a public Halloween countdown at `go.countdowncula.com/c/halloween` with a live preview, plus the Halloween voice pack. It's a small, timely way to measure whether live links get shared before the bigger phase 2 investment.

### Phase 1 progress

| Feature | State | Still to do |
|---|---|---|
| Server and live links (1) | Built | Atlas, Vercel and DNS setup, privacy policy update. Rate limiting is in (see `server/README.md`) |
| Animated share cards (6) | Built. Share Card menu on the detail screen offers the still image or a 6 second 1080 × 1920 video | Instagram Stories handoff is written but hidden until `InstagramStories.facebookAppID` is set (Meta requires an app ID) |
| The Count speaks (9) | Text lines built, with a Halloween week set (Oct 25 to 31). Toggle in the editor, on by default for vampire hours countdowns | Spoken final 10 seconds, waiting on the voice recordings |
| Sunrise and moon (10) | Built. "Vampire hours" in the new countdown menu: next sunrise, sunset and full moon. Rolls forward on every device | Nothing |

Sunrise and sunset use the NOAA sunrise equation, full moons use Meeus chapter 49. Both match published times to within a few minutes. Location is asked for once at reduced accuracy and stored rounded to 0.1°, so the watch and Mac can roll the date forward too.

Builds older than this one ignore `extras.voice` and `extras.auto`. If an older build edits one of these countdowns, it saves the extras without them, and the countdown turns back into a plain one-off date.

## Privacy and safety

Publishing is always an explicit action, and the share sheet says the countdown becomes visible to anyone with the link. Unpublish deletes the server copy and photo right away. Slugs are random, so links can't be enumerated. The server stores no names, emails or device identifiers in phase 1. The privacy policy on the site needs an update before phase 1 ships, since the app currently promises that data stays in iCloud.

Sensitive count-ups (sober, smoke-free) never appear in the crypt and show a confirmation before publishing.

## Open questions

1. ~~Is `go.countdowncula.com` the right domain, or `countdowncula.com/c/...` through a rewrite?~~ Decided: `go.countdowncula.com`. The app was renamed from Count Downula on October 7, 2026, so links use the new domain.
2. Who records the Count Downcula voice?
3. ~~Should shared countdown members be able to edit by default, or only the owner?~~ Decided: owner only in version one.
4. ~~Does the App Clip need to work on iPad, or iPhone only?~~ Decided: iPhone only, but Apple requires a clip to support the same devices as its parent app, so it runs on iPad too with a phone-width column.
