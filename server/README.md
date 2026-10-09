# Count Downcula server

Hosts published countdowns at `go.countdowncula.com/c/<slug>`: a live ticking page and a link preview image that renders on request, so a pasted link always shows today's number. Private countdowns never reach it. The app only sends a countdown here when you tap Share Live Link.

Built with Next.js (App Router), Material UI and MongoDB. See `docs/specs/viral-features.md` for where this is headed.

## Routes

| Route | What |
|---|---|
| `POST /api/countdowns` | Publish. Body `{ countdown, photo? }`. Returns `{ slug, url, ownerToken, countdown }` |
| `GET /api/countdowns/:slug` | Public JSON. After zero it adds `recap: { counted?, people, notes, closest }`, and a countdown kept counting up from zero has `keptCounting: true` |
| `PUT /api/countdowns/:slug` | Owner edit, `Authorization: Bearer <ownerToken>`. Leave `photo` out to keep it, `null` to remove it |
| `DELETE /api/countdowns/:slug` | Owner unpublish. Deletes the countdown and its photo |
| `GET /c/:slug` | The page |
| `GET /c/:slug/og` | 1200 × 630 PNG preview. The page's `og:image` adds `?d=<days left>` so chat apps that cache by URL refetch each day |
| `GET /c/:slug/photo` | The backdrop JPEG (a photo, or the app's scene rendered at 1080 × 1350) |
| `GET /c/:slug/calendar.ics` | The countdown as an iCalendar feed. The page's Add to Calendar offers it as a `webcal://` subscription, a Google Calendar subscription, or a download |
| `GET /embed/:slug` | A small live countdown for an iframe, `noindex`, canonical to the live page. Query options: `theme` (style, dark, light), `end` (message, recap, countup, hide), `message`. Only embeds may be framed by other sites (`frame-ancestors`); everything else is `'self'` |
| `GET /embed.js` | The one-line embed: `<script async src="https://go.countdowncula.com/embed.js" data-countdown="<slug>"></script>`, with optional `data-theme`, `data-end`, `data-message`, `data-width`, `data-height` |
| `POST /api/countdowns/:slug/host` | Applies a Host Pass, `{ transaction }` (StoreKit 2's signed JWS), checked against Apple's certificate chain. Owner only |
| `PUT /api/countdowns/:slug/alias` | Sets a hosted countdown's custom link, `{ alias }`. The proxy maps `/c/<alias>`, `/embed/<alias>` and `/api/countdowns/<alias>/…` to the real slug |
| `POST /api/countdowns/:slug/coffin/:id/video` | Adds a short video (raw MP4 under 4.3 MB) to your own note on a hosted countdown. `GET` returns it with the same rules as photos, which take `?i=` for a note's second, third or fourth photo |
| `GET /new` | Make a countdown in the browser (web create). It publishes through `POST /api/countdowns` and keeps the owner token in the browser's `localStorage` |
| `GET /c/:slug/edit` | Edit or delete with the owner token this browser holds, or one an emailed link brings in its fragment (`#t=<token>`, never sent to the server) |
| `POST /api/countdowns/:slug/edit-link` | Emails the owner an edit link, `{ email }`, `Authorization: Bearer <ownerToken>`. The address is used once and not stored. Answers `503` until a sending domain is set up |
| `GET /c/:slug/present` | The countdown full screen for a TV or projector, with a QR code to join |
| `GET /api/cron/crypt` | Daily (Vercel cron, `CRON_SECRET`). Keeps the next occurrence of every yearly holiday and fun day in the Crypt, from the rules in `src/lib/holidays.ts`, so each one comes back the day after it drops off. Sky events and sports are still loaded by hand from `crypt/launch.json` with `scripts/seed-crypt.mjs`; extend `LUNAR_NEW_YEAR` past 2035 when the time comes |
| `POST /api/events` | A batch of app-side events, `{ installId, platform, appVersion, events: [{ name, at, slug?, source? }] }`. See Metrics below |
| `GET /admin/metrics` | The metrics dashboard, behind HTTP Basic auth with `METRICS_PASSWORD` |

`countdown` uses the app's own JSON with ISO 8601 dates: `title`, `details`, `targetDate`, `createdAt`, `kind`, `timeZone`, and `style` and `milestones` exactly as Swift encodes them. The server stores only a SHA-256 hash of the owner token. The app keeps the token in the iCloud Keychain.

## Run it locally

```bash
cd server
npm install
cp .env.example .env.local        # point MONGODB_URI at Atlas or a local mongod
npm run dev                        # http://localhost:4300
```

If your global npm config sets `allow-scripts`, install with `NPM_CONFIG_USERCONFIG=/dev/null npm install`.

Point a debug iPhone build at it with the launch argument `-linkServer http://localhost:4300` (the simulator reaches your Mac's localhost).

## Tests

```bash
npm test                           # unit tests for time, style and validation
npm run typecheck
BASE=http://localhost:4300 npm run smoke   # publish, render, edit, unpublish against a running server
```

The app's `LiveServerLinkTests` checks the Swift side against a running server:

```bash
TEST_RUNNER_LINK_SERVER=http://localhost:4300 xcodebuild test -project Countdownula.xcodeproj -scheme CountdownulaTests -destination 'platform=macOS'
```

## Deploy

1. Create a MongoDB Atlas cluster and a database user. Allow Vercel's egress (or `0.0.0.0/0` with a strong password).
2. Create a Vercel project `countdowncula-server` from this repo with Root Directory `server`.
3. Set `MONGODB_URI`, `MONGODB_DB=countdowncula`, `PUBLIC_ORIGIN=https://go.countdowncula.com` and `RATE_LIMIT_SALT` (any long random string; it keeps the hashed client addresses from being guessable).
   For the metrics dashboard, set `METRICS_PASSWORD` (16 characters or more, any user name). Without it, `/admin/metrics` stays shut.
   For emailed edit links on countdowns made on the web, set `RESEND_API_KEY` and `EMAIL_FROM` (an address on a domain verified in Resend), and optionally `EMAIL_REPLY_TO` for where replies go. Without them, the editor doesn't offer the email, and only the browser that made a countdown can edit it.
   For instant updates to members, also set `APNS_KEY_ID`, `APNS_TEAM_ID` (`YZ36Z8GSEN`) and `APNS_PRIVATE_KEY` (the whole `.p8` file, mark it Sensitive). Without them the server skips pushes and members catch up when their app refreshes.
4. Add the domain `go.countdowncula.com` to the project and a `CNAME go → cname.vercel-dns.com` record.

Before the app ships with Share Live Link, update the privacy policy in `site/_src/privacy.html`: it currently says countdowns stay in iCloud.

## Metrics

Every event goes into one `events` collection, `{ name, slug?, platform, appVersion?, source?, installId?, at }`, removed by a TTL index after 13 months. Nothing in it names a person: no titles, IP addresses or member keys. `src/lib/events.ts` lists the event names.

- **Server events** are written as they happen: `publish`, `unpublish`, `join`, `leave`, `coffin_drop`, `pool_guess`, `wallet_pass_download`, `wallet_pass_add` and `page_view`. The platform comes from the app's `X-Countdowncula-Client: ios/1.2.0` header, or `web` for a browser. A page view's `source` is `?src=` when the link carries one (the Wallet pass QR code uses `?src=wallet`), otherwise the referring site's host.
- **App events** come in batches from `Sources/Shared/Analytics.swift`: `active` (once a day), `countdown_created` (with how, such as `typed`, `screenshot`, `template`, `quick_timer` or `siri`), `share_sheet_opened`, `image_exported`, `video_exported`, `paywall_shown` (with why), `purchase_completed`, `install_from_link`, `clip_launch` and `clip_keep_it`. Each carries a random install ID the app makes up and can reset. The server drops names it doesn't know, so newer apps never get an error. The apps stop sending when Share Analytics is off, and the watch doesn't send any.

The dashboard at `/admin/metrics` shows the north star (countdowns shared per active install, by month), new installs that arrived with a link, paywall to purchase, the link funnel, participation by platform, weekly cohorts, and top sources.

## Rate limits

Writes are counted in MongoDB (`rateLimits`, fixed windows, removed by a TTL index), so the limits hold across serverless instances. Clients are identified by a salted hash of their IP address, which is dropped when its window ends.

| Action | Limit |
|---|---|
| Publish | 10 an hour and 30 a day per client, 2,000 an hour for everyone together |
| Edit | 120 an hour per client, 60 an hour per countdown |
| Unpublish | 60 an hour per client |
| Event batches | 60 an hour per client |
| Emailed edit links | 5 an hour per client, 10 a day per countdown |
| Coffin drops from the web (guests) | 6 an hour per client and 100 an hour per countdown, on top of the coffin's own limits |

Over a limit, the API answers `429` with `Retry-After` and a message the app shows as is. Reading pages and preview images isn't limited; the CDN caches those. The limits live in `src/lib/rateLimit.ts`. Vercel Firewall rules can sit in front of this for floods, but they aren't needed to launch.

## Not yet in place

Abuse reporting, and the App Clip's `apple-app-site-association` file (phase 2).
