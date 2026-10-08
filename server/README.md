# Count Downcula server

Hosts published countdowns at `go.countdowncula.com/c/<slug>`: a live ticking page and a link preview image that renders on request, so a pasted link always shows today's number. Private countdowns never reach it. The app only sends a countdown here when you tap Share Live Link.

Built with Next.js (App Router), Material UI and MongoDB. See `docs/specs/viral-features.md` for where this is headed.

## Routes

| Route | What |
|---|---|
| `POST /api/countdowns` | Publish. Body `{ countdown, photo? }`. Returns `{ slug, url, ownerToken, countdown }` |
| `GET /api/countdowns/:slug` | Public JSON |
| `PUT /api/countdowns/:slug` | Owner edit, `Authorization: Bearer <ownerToken>`. Leave `photo` out to keep it, `null` to remove it |
| `DELETE /api/countdowns/:slug` | Owner unpublish. Deletes the countdown and its photo |
| `GET /c/:slug` | The page |
| `GET /c/:slug/og` | 1200 × 630 PNG preview. The page's `og:image` adds `?d=<days left>` so chat apps that cache by URL refetch each day |
| `GET /c/:slug/photo` | The backdrop JPEG (a photo, or the app's scene rendered at 1080 × 1350) |

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
4. Add the domain `go.countdowncula.com` to the project and a `CNAME go → cname.vercel-dns.com` record.

Before the app ships with Share Live Link, update the privacy policy in `site/_src/privacy.html`: it currently says countdowns stay in iCloud.

## Rate limits

Writes are counted in MongoDB (`rateLimits`, fixed windows, removed by a TTL index), so the limits hold across serverless instances. Clients are identified by a salted hash of their IP address, which is dropped when its window ends.

| Action | Limit |
|---|---|
| Publish | 10 an hour and 30 a day per client, 2,000 an hour for everyone together |
| Edit | 120 an hour per client, 60 an hour per countdown |
| Unpublish | 60 an hour per client |

Over a limit, the API answers `429` with `Retry-After` and a message the app shows as is. Reading pages and preview images isn't limited; the CDN caches those. The limits live in `src/lib/rateLimit.ts`. Vercel Firewall rules can sit in front of this for floods, but they aren't needed to launch.

## Not yet in place

Abuse reporting, and the App Clip's `apple-app-site-association` file (phase 2).
