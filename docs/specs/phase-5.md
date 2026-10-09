# Count Downcula phase 5: measure, extend the moment, widen the loop

Status: draft, October 9, 2026
Owner: Michael Lynn
Builds on: [what shipped](viral-features.md) and [what the others do](competitive-landscape.md)

## Why this phase exists

Phases 1 through 4 built the sharing loop. Phase 5 makes it measurable, fixes the three places where it leaks, and catches up on the basics competitors already have.

It can't be measured. There are no analytics in the app, and the server only keeps per-countdown counters. You can't tell which of the 12 features brings in new users.

It ends at zero. Zero is the peak of every shared countdown: the coffin opens, the pool settles, and every phone celebrates at once. Then the app has nothing more to offer, and most countdowns get deleted.

It stops at the iPhone. About 40% of US phones run Android, and more in most other markets. On the web today, those people can watch and guess in a pool, but they can't join, add to the coffin or get reminders.

It's behind on the basics. Next to the [competition](competitive-landscape.md), the sharing features have no equal: nobody else has Wallet passes, an App Clip, a sealed coffin, date pools or synchronized zero. But repeats stop at yearly, there's no Calendar or Contacts import, the widgets can't be tapped to do anything, there are no Mac desktop widgets, and every countdown counts in days and hours.

Nobody owns the big screen. The only Mac countdown screensaver is an open-source project last updated about 7 years ago. Apple TV countdown apps are small and none sync with a phone. Nothing is made for a TV at a party, and that's where shared zeros get filmed.

Phase 5 also fills gaps in how countdowns get created, claims the system surfaces that are still empty, and sets up pricing that pays for the server.

## Goals and metrics

| Metric | Why it matters | Baseline |
|---|---|---|
| Shared countdowns per active user per month | The north star from the original spec | Unknown until 5.1 ships |
| Share of new installs from a link | Is the loop pulling people in | Unknown |
| Countdowns kept 30 days after zero | Does the after-zero work stop deletion | Unknown |
| Non-iPhone participants per shared countdown | Does the web widen the loop | Pool guesses only today |
| Countdowns created in a user's first session | Does import lower the cost of starting | Unknown |
| Big-screen sessions at zero | Do people put the moment on a TV or a Mac | None today |
| Paying users and revenue per shared countdown | Does pricing follow server costs | Unlimited sales only |

The first job of 5.1 is to fill in that baseline column before anything else ships.

## Two deadlines

**Halloween**, October 31, is 22 days out, and it's already in the crypt at `/c/halloween-2026`. It's the first big public zero the app will have. If measurement (5.1) and the zero recap (5.2) ship before then, Halloween becomes the first real test of both.

**New Year's Eve**, December 31, is 83 days out. It's the biggest shared zero of the year, and the one people watch on a TV. The big-screen work (5.9) should be ready for it, and its web part is small enough to try on Halloween too.

Everything else in this plan can follow on its own schedule.

## The workstreams

Sizes follow the original spec: S is days, M is a week or two, L is several weeks.

### 5.1 Measurement (size S to M, ship first)

What it is: an event log and a small metrics dashboard, so every later feature ships with a number attached.

How it works: most of the loop already touches the server. Publish, join, leave, coffin drops, pool guesses, Wallet pass adds, App Clip launches and page views can each write one document to a new `events` collection as they happen. Use `{ name, slug?, platform, appVersion, source?, at }`, with a TTL index at 13 months. That covers the sharing loop with no client changes.

Events that never reach the server need a small client path: countdown created (and how, whether typed, from a screenshot, from a template or later from Calendar), share sheet opened, video exported, paywall shown, purchase completed, and a once-a-day active ping. These go to `POST /api/events` in batches, tagged with a random install ID that the app generates and can reset. It should never use the device's advertising or vendor identifier.

Attribution comes almost free. The App Clip's Keep It already leaves the slug in the App Group, and the full app reads it on first launch. Logging `install_from_link` at that moment answers the question of how many installs came from a link.

The dashboard lives at `/admin/metrics` in the existing server, built with Material UI and Atlas aggregation pipelines. It shows the north star, the funnel from page view to Clip launch to Keep It to install, and weekly cohorts.

The alternative is TelemetryDeck for the app-side events. It's privacy-focused and quick to add, but it splits your data across two places and adds a vendor to the privacy policy. Keeping everything in Atlas means one query language and one dashboard.

Privacy: update the privacy policy and the App Store privacy label (usage data, not linked to identity) before this ships. Add a Share Analytics toggle in settings, on by default.

Depends on: nothing new.

Built (October 9, 2026): everything in Atlas, no TelemetryDeck. The server writes nine events as they happen and takes app batches at `POST /api/events`, dropping names it doesn't know. The apps send a `X-Countdowncula-Client` header so server events know the platform, and the Wallet pass QR code links with `?src=wallet`. On the app side, `Analytics` queues events in UserDefaults and sends them when the app comes forward or goes to the background, with a random install ID. Share Analytics is a switch in the iPhone's Settings app (with Reset Analytics ID) and in the Mac popover's privacy menu. The watch sends nothing for now, since it has nowhere to put the switch. The dashboard is at `/admin/metrics`, behind Basic auth with `METRICS_PASSWORD`. The privacy manifest declares product interaction and a device ID, both unlinked and used for analytics. The privacy policy and the site's FAQ are drafted but not yet published. "Countdowns kept 30 days after zero" waits for 5.2, which adds the events it needs.

### 5.2 After zero (size M)

What it is: three things that happen when a countdown reaches zero, so the moment people waited for becomes something they share and keep.

The recap card. At zero, the app offers a recap as a still or a video, reusing `ShareCardView` and `ShareVideo`. For a solo countdown it reads like "Sonoma. 142 days counted." A shared countdown adds the people: "Sonoma. 142 days. 23 of us. 41 sealed notes. Dana guessed closest." It's the most shareable image the app can make, and today it doesn't exist.

The recap page. After zero, `/c/<slug>` turns into a recap: the final stats, the pool result, and for members the opened coffin. Its preview image switches from "3 days left" to "It happened. 23 counted down together." People keep sharing the link after the event, and every view still carries the download button. Crypt entries get the same treatment with their subscriber count.

Keep Counting. A one-tap rollover turns the finished countdown into a count-up from its target date. "Days until the wedding" becomes "Married 1 year." The count-up kind, yearly milestones and repeat logic already exist. For shared countdowns, the owner's choice flows to members, and each member can opt out.

The rest go somewhere better than deletion. Finished countdowns that aren't rolled over move to a Past section (call it the Graveyard if you like the joke), with their recap card ready to reshare on the anniversary.

Depends on: 5.1 to measure it. Nothing new for the build.

Measure: recap shares per finished countdown, Keep Counting rate, and countdowns still present 30 days after zero.

Built (October 9, 2026):
- **Recap card:** after zero, the share card and video become the recap. "Sonoma", "142 days", "counted · October 24, 2026". A shared countdown adds "23 of us · 41 notes in the coffin · Dana guessed closest". The server works out the people, and `GET /api/countdowns/<slug>` returns them as `recap`.
- **Recap page:** after zero, `/c/<slug>` reads "It happened." and shows the counted days and the people line. Its preview image and description become "It happened. 23 counted down together." The "Count down with me" and Wallet buttons give way to Get the App. Floating holidays wait for each viewer's own zero.
- **The coffin on the web:** the page only says the coffin is open in the app. Opening it on the web waits for 5.3.
- **Keep Counting:** a button on a finished countdown's detail screen turns it into a count-up from its zero, with the count-up milestones. When the owner does it, the server marks the countdown `keptCounting`, and members follow. Each member has a "Keep counting with everyone" switch to stay at zero instead (`staysFinished` on their subscription). Kept countdowns keep their recap and their coffin.
- **Past countdowns:** finished countdowns stay in Past, as before. They lose Wallet and Invite Others and gain Share the Recap. Each one comes back on its anniversary with a notification.
- **Not built:** I didn't add a Graveyard name, and Mac has no Keep Counting button yet. A Mac still shows a kept countdown as a count-up.
- **Events:** `countdown_finished` (iPhone, once per countdown, only within a week of zero), `keep_counting` (solo, shared, member_follows, member_stays) and `countdown_deleted` (before_zero, after_zero_30d, after_zero_later, count_up or timer). Recap shares are `image_exported` and `video_exported` with source `recap`. The dashboard has an After Zero section.

### 5.3 The web loop (size M, web create is L)

What it is: let people without an iPhone take part, and put countdowns on other people's websites.

Coffin from the web. Anyone with the link can leave a note and a photo on the live page with a typed name, using the browser key pattern date pools already use. The same seal, report and remove rules apply, with tighter rate limits for web writes.

Calendar feeds. Each shared countdown gets `/c/<slug>/calendar.ics`, plus a `webcal://` subscribe link and an Add to Google Calendar button on the page. A subscription follows owner edits, so an Android guest's calendar moves when the wedding date does.

Embeds. `go.countdowncula.com/embed/<slug>` serves a small live countdown for an iframe, with size and theme options, and a one-line `<script>` that inserts it. Each embed links back with "Made with Count Downcula." The embed route allows any `frame-ancestors`, stays `noindex` and points its canonical tag at the live page. "Countdown timer for website" is a big search category, and each embed is a lasting backlink. Track `embedViews` in stats.

Embeds also need **end actions**, because the web tools they compete with (Elfsight, TickCounter, Jotform) all have them: at zero, show a message, switch to the 5.2 recap, count up, or hide. A redirect option waits for the host tier, since an open redirect on our domain is a phishing tool. Elfsight charges from $4 a month for this, which makes branding removal a natural host-tier feature (5.6).

Web create (decision needed). An Android user who sees a great countdown page can't make their own. A web editor at `go.countdowncula.com/new` that stores the owner token in the browser, with an optional emailed edit link, would close that. It would also turn the server into a second place where countdowns get made. It's a real product decision, so it's listed separately.

Depends on: nothing new for the first three. Web create would need its own spec.

Measure: web coffin drops, calendar subscriptions, embed views and click-throughs, and non-iPhone participants per shared countdown.

Built (October 9, 2026), everything except web create:
- **Web coffin:** the live page has a coffin panel. A browser's first drop gets a guest key (the server keeps only its hash), and the key lets the guest see and remove their own drops before zero. At zero, guests open the coffin along with the owner and members. Guests can report, and the same remove and review flow applies. Guest drops are limited to 6 an hour per client and 100 an hour per countdown.
- **Calendar feeds:** `/c/<slug>/calendar.ics` is the feed.
  - A countdown to midnight in the owner's zone becomes an all-day event. Floating holidays stay floating.
  - Count-ups repeat yearly, and pools that haven't settled say "(estimate)".
  - The feed asks subscribers to refresh hourly.
  - The page's Add to Calendar offers webcal:// (Apple and Outlook), a Google Calendar subscription, and a download.
  - Subscriptions are counted by salted address hash and forgotten after 45 days. Google fetches for many people from shared addresses, so its count runs low.
- **Embeds:** `/embed/<slug>` and `/embed.js`.
  - The countdown can use its own style, or a dark or light theme.
  - At zero it can show a message, the recap, a count-up, or nothing.
  - Each embed carries a "Made with Count Downcula" link back to the live page (`?src=embed`).
  - Plain count-ups can't be embedded.
  - Only embeds may be framed by other sites; every other page now sends `frame-ancestors 'self'`.
  - The live page has "Embed on your site", and the app's live link section has Copy Embed Code.
  - Embed views count into `stats.embedViews` and an `embed_view` event that records the embedding site's name.
- **Not built yet:** redirects at zero wait for the host tier.
- **Dashboard:** a new Web Loop section.

### 5.4 Calendar import and more repeats (size M)

What it is: start people with the dates they already have, and give them countdowns they check every week instead of a few times a year. Both are table stakes. Countdowns (Shayes), Pretty Progress, Time Until and Outside all import from Calendar, and most competitors repeat more often than yearly.

From Calendar. A picker shows the next 90 days of events, and you tick the ones you want. Each becomes a countdown with a fitting scene chosen from the title. Offer it in onboarding and in the + menu, on iPhone and Mac. It needs full calendar access (`requestFullAccessToEvents` on iOS 17) and the calendar entitlement for the sandboxed Mac build. Version one is a one-time import that stores the event identifier in extras, so a later version can offer "update from Calendar."

From Contacts. Pick people and turn their birthdays into yearly countdowns. The iOS 18 limited-access contact picker means you never ask for the whole address book. Only one competitor, Countdowns (Shayes), does this.

More repeats. Today the only repeat is yearly. Add weekly (Friday at 5pm), monthly (payday, rent), every N days, and weekdays. In extras, generalize `repeatsYearly` into a `repeat` object, and keep writing `repeatsYearly` for yearly ones so older builds still roll birthdays forward.

The older-build risk applies here. A build from before this one that edits a weekly countdown drops the new field, and the countdown becomes a one-off. Since the App Store version will be recent, that's acceptable, but release notes should mention it.

Decision needed: do imported countdowns count toward the free limit of 3? Import makes it easy to blow past 3 in one tap. Either the limit applies and import becomes a strong upgrade moment, or the import grants a one-time allowance. Keep in mind that several competitors give unlimited countdowns free and charge for looks or sync, so 3 is already strict. 5.1 should measure the paywall view to purchase rate before you pick.

Depends on: nothing new.

Measure: countdowns created in the first session, and weekly active users among people with a weekly repeat.

Built (October 9, 2026), on iPhone. Decision: imports count toward the free limit.
- **From Calendar:** in the + menu and the empty state. The sheet lists the next 90 days of events, with each repeating event shown once.
  - Each pick becomes a countdown with a scene chosen from its title and place, and the event's identifier saved in extras as `calendarEvent`.
  - Repeats on a fixed date (yearly, monthly, weekly, daily, every N weeks, weekdays) come with it. Rules like "the fourth Thursday" import as one-offs.
  - Full calendar access is asked for when the sheet opens.
- **Birthdays from Contacts:** this uses the system contact picker, which runs outside the app, so there's no Contacts permission prompt at all. Only people with a birthday can be picked. Each becomes a yearly countdown to the start of the day. A Feb 29 birthday lands on Feb 28 in common years.
- **The free limit:** what fits the free tier is added, soonest first. The rest wait on the Unlimited offer (paywall reason `import_limit`) and are added if Unlimited is bought. Otherwise a notice names what didn't fit.
- **More repeats:** the editor's yearly switch is now a Repeats picker: every day, every weekday, every week, every few days (2 to 365), every month, every year.
  - Stored as `repeat` in extras. `repeatsYearly` is still written for yearly repeats, so older builds keep rolling birthdays.
  - Monthly and yearly count from the original date, so the 31st and Feb 29 come back when they exist.
  - Grace periods shrink for frequent repeats: a day for yearly and monthly, 6 hours for weekly and every 3 or more days, and an hour for weekdays and daily.
- **Debug launch argument:** `-openImport calendar` (or `contacts`) opens a picker at launch, for screenshots.
- **Not built yet:** the Mac. It needs the calendar entitlement in the sandboxed build and its own picker. Countdowns imported on the iPhone sync to it as usual.

### 5.5 System surfaces (size M)

What it is: put Count Downcula in the places iOS and macOS added that the app hasn't claimed yet. No competitor lists interactive widgets or Control Center controls, so this is cheap ground to take first.

| Surface | What it does | Notes |
|---|---|---|
| Notification actions | Put on Lock Screen (in the final 8 hours), Share, and Open the Coffin at zero | `UNNotificationCategory` per alert type, mirrored on Watch where it makes sense |
| Interactive widgets | Start the Live Activity, pin or unpin, and cycle countdowns, right from the widget | `Button(intent:)` with App Intents, iOS 17 |
| Control Center and Lock Screen controls | A Quick Timer button that starts a timer with its Live Activity, and a Next Up control showing your pinned countdown | `ControlWidget`, iOS 18 and later, gated with `@available` since the app targets iOS 17 |
| Mac widgets | Desktop and Notification Center widgets reusing the iPhone widget views, including the Up Next list | A new macOS widget extension reading the same `WidgetSnapshot` |
| Extra-large widget | The countdown photo and time left at `systemExtraLarge` on iPad and the Mac desktop | Today the widgets stop at large |

The notification actions are the cheapest and probably the most valuable here, because every milestone alert already reaches people and today offers no next step.

Built, notification actions (October 9, 2026):
- **Buttons:** each alert the iPhone schedules gets a category, and long-pressing it shows the matching buttons.
  - Milestones in the final 8 hours: Put on Lock Screen and Share.
  - Other milestones: Share.
  - Zero: Share the Recap, plus Open the Coffin on shared countdowns that have a coffin.
  - Anniversaries: Share the Recap.
  - Timers, birthdays and sunrises get no buttons at zero, since they roll on.
- **What a tap does:** every button opens the app. Put on Lock Screen starts the Live Activity, because ActivityKit needs the app in the foreground. Share renders the card, or the recap after zero, into the share sheet. Open the Coffin opens the reveal.
- **Events:** each tap logs `notification_action` with the button as its source.
- **Watch:** nothing new. These actions need the phone. When a forwarded alert shows them on the watch, tapping one just opens the watch app.

Mac widgets matter more than the draft first said. macOS Sonoma can show iPhone widgets on the desktop, but only when the iPhone is nearby on the same Apple Account, and tapping one asks you to open the app on the iPhone. A native widget works for Mac-only users and opens the menu bar app. The only well-reviewed competitor with native Mac widgets is Countdowns (Shayes), and we already have the Mac app, the widget views and the snapshot.

Depends on: nothing new.

Measure: control and widget taps, actions taken from notifications, and Mac widget installs.

### 5.6 The host tier (size L)

What it is: pricing that charges the people who get the most from sharing.

The problem. Unlimited is a one-time $2.99, and joined countdowns are free. Meanwhile APNs, the cron job, Blob storage and Wallet updates all grow with the biggest shared countdowns, and the people in them are often free users. A one-time purchase pays once for costs that keep going.

The market says $2.99 is low. Competitors' lifetime prices run $19.99 to $59.99, and their subscriptions run about $10 to $45 a year. Outside, the closest competitor, sells a Pro subscription on top of free sharing. Raising Unlimited is a separate question from the host tier, and 5.1 can test it.

The proposal. Keep Unlimited. Add hosting on top, aimed at the person running the event. The candidate features are a custom link (`/c/sarah-and-tom`), video and multiple photos in the coffin, a keepsake export after zero (every note and photo as a PDF and a ZIP, like a guestbook), the Count Downcula branding removed from the page and embeds, embed redirects at zero, and member names.

Two ways to sell it, and they suit different buyers:

| Model | Fits | Tradeoff |
|---|---|---|
| Per-event Host Pass (consumable in-app purchase applied to one slug) | Weddings, birthdays, reunions, one big date | Easy to understand. The server has to verify the transaction with the App Store Server API and attach it to a slug |
| Subscription | Creators and businesses running launch countdowns and embeds | Recurring revenue that matches recurring cost, but it's a harder sell for a once-a-year wedding |

My recommendation is to start with the Host Pass, since weddings and parties are the core of the shared loop, and add a subscription later if embeds pull in business users. I don't know the right price. Use 5.1 to test it rather than guess. Both models go through in-app purchase because they unlock digital features.

Member names probably bring back Sign in with Apple, deferred from phase 2. A lighter version uses typed names, the way the coffin and pools already work.

Depends on: 5.1, App Store Server API keys, a product decision on the model.

Measure: Host Pass conversion among shared countdowns with 10 or more members, and revenue per shared countdown against server cost.

### 5.7 Localization (size M, ongoing)

What it is: the app, the pages and the App Store listing in more languages.

How it works: move every target to String Catalogs (`.xcstrings`). Localize the live page, crypt and embeds by `Accept-Language`. Start with Japanese, German, Spanish, Brazilian Portuguese and French, chosen by App Store market size. Add crypt entries that matter outside the US, such as Diwali, Eid al-Fitr, Carnival and Golden Week, held to the same rule of fixed, verifiable dates with sources. The Count's voice lines need a transcreator who can write the character in each language, not a literal translation. That's a later step.

Korean is worth a look. TheDayBefore, a Korean "D-day" app, has a 4.8 rating, which shows a market that counts down to everything.

Depends on: a translation vendor or reviewers for each language.

Measure: installs and active users by storefront.

### 5.8 Ways to count (size S to M)

What it is: let each countdown count in the unit that fits it, and in the right time zone. Today everything reads as days and hours.

Units. A per-countdown display unit in extras, used by the detail view, widgets, complications, the menu bar, the live page and share cards:

| Unit | Reads as | Who has it |
|---|---|---|
| Days and hours | 47d 3h (today's default) | everyone |
| Weeks | 6 weeks, 5 days | a few apps |
| Sleeps | 12 sleeps | only single-purpose apps (How Many Sleeps, Sleeps Countdown) |
| Workdays | 33 workdays | CountdownBar, Working Days Counter, a few small apps |
| Weekends | 7 weekends | nobody found |
| Percent | 82% of the way there | Pretty Progress shows progress bars |

Sleeps is the cheap, shareable one: it's how kids count to a birthday or Christmas, and it makes a good share card. Count a sleep at each local midnight before the target, with an option for a bedtime.

Workdays skip weekends in version one. Public holidays by region are a later step, and they can come from the same verified dates the crypt uses. A weekly-repeat payday or a "last day at work" countdown in workdays is a strong reason to keep the app.

Time zones. Add an optional time zone to an event countdown, so "landing in Tokyo at 6:40pm" means Tokyo time wherever you are. Store it in extras. Today the server and crypt have floating local times for holidays, and shared countdowns already send the owner's time zone for Wallet, so this extends what's there. Show both times in the detail view when they differ.

The older-build risk is mild. An older build ignores the unit and shows days and hours, which is still correct. An older build ignoring the time zone would still count to the same instant, since `targetDate` stays an absolute date.

Depends on: nothing new.

Measure: share of countdowns using each unit, and share cards made from them.

### 5.9 The big screen (size S for the web, M for the Mac, L for Apple TV)

What it is: put a countdown on a TV, a projector or an idle Mac, for the parties, launches and New Year's Eves where people watch zero together. Nobody owns this. The only Mac countdown screensaver is soffes/Countdown, open source and last updated about 7 years ago, and the Apple TV apps don't sync with anything.

Present mode on the web (S). `/c/<slug>/present` shows the countdown full screen in the countdown's style, with huge digits, the final-10-seconds treatment, confetti at zero, and the screen kept awake with the Wake Lock API. It works on any smart TV browser, a laptop on a projector, or AirPlay from Safari. Add a Present button to the live page and a QR code in the corner so people in the room can join from their phones. That turns every party screen into an install prompt. This is the piece to try on Halloween.

Full screen on the Mac (S). A Present command in the menu bar app and on each countdown's detail view, opening the same layout full screen on any display.

External display from the iPhone (S to M). When an iPhone is connected to a TV by AirPlay or a cable, show the presentation view on the TV and keep the controls on the phone, using a second `UIWindowScene` for the external display role.

Mac screensaver (M, spike first). A `.saver` bundle that cycles through pinned countdowns, or shows one you pick, in their styles, built on `ScreenSaverView`. Three risks to settle in a spike before committing:

- Since macOS 10.15, third-party screensavers run inside Apple's `legacyScreenSaver` host, which has known bugs on recent macOS (instances that don't stop, repeated preview loads). Test on Sonoma and the current release.
- The Mac App Store doesn't distribute screensavers. Ship it inside the GitHub direct build and as a download from countdowncula.com, installed by double-clicking.
- The screensaver runs in its own sandbox and can't read the app's data store. Options are a snapshot file the direct build writes where the screensaver can read it, or having the screensaver fetch published countdowns from the server. The spike should pick one.

Apple TV app (L, later). A tvOS app with a top shelf, synced through iCloud, that shows your countdowns and the crypt and joins shared countdowns. It would be the only Apple TV countdown app that syncs with a phone. Hold it until present mode shows there's demand.

Depends on: nothing new for present mode. The screensaver needs the spike.

Measure: present-mode sessions, how many are open at zero, and joins from the room QR code.

### Considered, not planned

- **AI-generated backgrounds.** DayDrop has them. Apple's Image Playground can do it on device for free. A nice addition to the style editor, but it doesn't move a metric in this phase.
- **Video backgrounds.** Widgets can't play video, so it would only work in the app.
- **Countdown wallpapers.** A static wallpaper goes stale the next day. Lock Screen widgets do the same job and stay current.
- **Focus filters.** No competitor has them, and the benefit is small.
- **visionOS.** The iPad app already runs there.
- **Group chat or a daily photo,** as in Outside Pro. The coffin covers the same need in a way that's ours.

## Sequence

| Order | Workstream | Size | Ships by | Needs from you |
|---|---|---|---|---|
| 1 | 5.1 Measurement | S to M | Before Halloween | Analytics approach, privacy policy sign-off |
| 2 | 5.2 After zero | M | Before Halloween | Nothing new |
| 3 | 5.9 Present mode on the web | S | Halloween if there's room, otherwise November | Nothing new |
| 4 | 5.5 Notification actions | S | Early November | Nothing new |
| 5 | 5.3 Web coffin, calendar feeds, embeds | M | November | Embed branding rules |
| 6 | 5.4 Calendar import and repeats | M | November | Free tier decision for imports |
| 7 | 5.8 Ways to count | S to M | November | Nothing new |
| 8 | 5.9 Mac full screen, iPhone external display, screensaver spike | M | Before New Year's Eve | Screensaver go or no-go after the spike |
| 9 | 5.5 Remaining surfaces, Mac widgets first | M | December | Nothing new |
| 10 | 5.6 Host tier | L | Before the spring wedding season | Pricing model, App Store Server API key |
| 11 | 5.7 Localization | M, ongoing | Rolling | Languages, translators |
| 12 | 5.9 Apple TV app | L | 2027, if present mode shows demand | Go or no-go |

## Carried over from phases 1 to 4

These are small and unblock features that are already built. Confirm the APNs key is set on Vercel, since silent pushes, synchronized zero and the pool settle push all wait on it. Record the Count's voice to replace the placeholder. Get a Meta app ID to turn on the Instagram Stories handoff. Automate the yearly reseed of crypt holidays, before New Year's Eve if possible, since every holiday drops off a day after zero.

## Decisions needed

1. Analytics: everything in Atlas, or TelemetryDeck for app events?
2. Do Calendar and Contacts imports count toward the free limit?
3. Build web create now, or keep creation in the app?
4. Host tier: Host Pass, subscription, or both? And does Unlimited stay at $2.99?
5. Which languages go first?
6. Who records the Count's voice?
7. Screensaver: build it after the spike, or stop at full-screen present mode?

## Privacy and safety

Analytics events carry no names, emails, contacts or calendar contents, only event names, counts and a resettable install ID. Calendar and Contacts data stays on the device. Only the countdowns you create from them reach iCloud, and only the ones you share reach the server. Web coffin drops go through the same seal, report and remove flow as app drops. Embeds and present mode never show coffin content or member counts for link-only countdowns unless the owner allows it. Sensitive count-ups (sober, smoke-free) skip the recap prompt and never appear in embeds by default. Embed redirects, if they ship, are limited to host-tier countdowns so the domain can't be used to bounce people to phishing pages.
