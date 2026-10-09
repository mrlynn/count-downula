import type { Collection } from "mongodb";
import { db } from "./mongo.ts";
import { isUnit, type Unit } from "./units.ts";
import { isSlug } from "./validate.ts";

/**
 * The event log behind /admin/metrics. One document per thing that happened: no names, emails,
 * countdown titles or IP addresses, only what happened, to which slug, from which platform and,
 * for app events, a random install ID the app can reset. Documents expire after 13 months.
 */

/** Things the server sees happen on its own. */
export const SERVER_EVENTS = [
  "publish", "unpublish", "join", "leave", "coffin_drop", "pool_guess",
  "wallet_pass_download", "wallet_pass_add", "page_view",
  // The web loop (5.3): an embed shown on someone's site, and a new calendar feed client.
  "embed_view", "calendar_subscribed",
  // The host tier (5.6): a Host Pass applied to a countdown; source is production, sandbox or xcode.
  "host_pass_applied",
  // The big screen (5.9): the web's present page opened, and still open at zero (source "web").
  "present_view", "present_zero",
  // Web create: the /new editor opened (source "live" from a live page's Make your own). Countdowns
  // made there are publish events from the web platform.
  "new_view",
] as const;

/** Things only the app knows about, sent in batches to POST /api/events. */
export const CLIENT_EVENTS = [
  "active", "countdown_created", "share_sheet_opened", "video_exported", "image_exported",
  "paywall_shown", "purchase_completed", "install_from_link", "clip_launch", "clip_keep_it",
  // After zero (5.2). A deletion's source says when: "before_zero", "after_zero_30d" (within 30 days
  // of zero) or "after_zero_later".
  "countdown_finished", "keep_counting", "countdown_deleted",
  // A button under an alert (5.5): source is lockscreen, share, recap or coffin.
  "notification_action",
  // A widget button or Control Center control (5.5): source is pin, lockscreen, quick_timer or open.
  "widget_action",
  // Ways to count (5.8): an edit that switched a countdown to a unit. Creations and exported cards
  // carry the unit too.
  "unit_chosen",
  // The big screen (5.9): presenting from the app (source "mac" or "tv"), and still presenting at zero.
  "present_started", "present_zero",
] as const;

export type EventName = (typeof SERVER_EVENTS)[number] | (typeof CLIENT_EVENTS)[number];

export const PLATFORMS = ["ios", "ipados", "macos", "watchos", "tvos", "clip", "web", "unknown"] as const;
export type Platform = (typeof PLATFORMS)[number];

export interface EventDoc {
  name: EventName;
  slug?: string;
  platform: Platform;
  appVersion?: string;
  /** How or where: "screenshot" for a countdown made from one, "free_limit" for a paywall, a referrer host for a view. */
  source?: string;
  /** What the countdown counts in, when it isn't days and hours (5.8). */
  unit?: Unit;
  installId?: string;
  at: Date;
}

/** About 13 months, so a full year of cohorts is always on hand. */
export const RETENTION_SECONDS = 395 * 86_400;

const SOURCE = /^[a-z0-9_.-]{1,40}$/;
const VERSION = /^[0-9][0-9A-Za-z.+-]{0,23}$/;
const INSTALL_ID = /^[A-Za-z0-9-]{16,64}$/;

/**
 * Which app sent a request. The app sends `X-Countdowncula-Client: ios/1.2.0`; anything else with a
 * browser user agent is the web, and the rest (older builds, scripts) is unknown.
 */
type HasHeaders = { headers: { get(name: string): string | null } };

export function clientOf(request: HasHeaders): { platform: Platform; appVersion?: string } {
  const header = request.headers.get("x-countdowncula-client") ?? "";
  const match = /^([a-z]+)\/(\S+)$/.exec(header.trim());
  if (match && (PLATFORMS as readonly string[]).includes(match[1]) && match[1] !== "web") {
    return { platform: match[1] as Platform, ...(VERSION.test(match[2]) ? { appVersion: match[2] } : {}) };
  }
  const agent = request.headers.get("user-agent") ?? "";
  return { platform: /Mozilla\//.test(agent) ? "web" : "unknown" };
}

/** "messages", "google.com": just the host a page view came from, never the full URL. */
export function referrerSource(referrer: string | null, ownHost: string): string | undefined {
  if (!referrer) return undefined;
  try {
    const host = new URL(referrer).hostname.replace(/^www\./, "").toLowerCase();
    if (!host || host === ownHost) return undefined;
    return SOURCE.test(host) ? host : undefined;
  } catch {
    return undefined;
  }
}

let indexesReady: Promise<unknown> | undefined;

export async function events(): Promise<Collection<EventDoc>> {
  const collection = (await db()).collection<EventDoc>("events");
  indexesReady ??= Promise.all([
    collection.createIndex({ at: 1 }, { expireAfterSeconds: RETENTION_SECONDS }),
    collection.createIndex({ name: 1, at: 1 }),
    collection.createIndex({ installId: 1, at: 1 }, { sparse: true }),
  ]);
  await indexesReady;
  return collection;
}

/** Records one server-side event. Never throws: losing a count is better than failing a request. */
export async function logEvent(
  name: (typeof SERVER_EVENTS)[number],
  request: HasHeaders | null,
  fields: { slug?: string; source?: string } = {},
): Promise<void> {
  try {
    const client = request ? clientOf(request) : { platform: "unknown" as const };
    const doc: EventDoc = { name, platform: client.platform, at: new Date() };
    if ("appVersion" in client && client.appVersion) doc.appVersion = client.appVersion;
    if (fields.slug && isSlug(fields.slug)) doc.slug = fields.slug;
    if (fields.source && SOURCE.test(fields.source)) doc.source = fields.source;
    await (await events()).insertOne(doc);
  } catch {}
}

export const BATCH_LIMIT = 100;
/** The app keeps events while offline, but anything older than this is stale. */
const MAX_AGE_MS = 30 * 86_400_000;
const MAX_SKEW_MS = 10 * 60_000;

export type BatchResult = { ok: true; docs: EventDoc[]; dropped: number } | { ok: false; error: string };

/**
 * Checks a batch from the app: `{ installId, platform, appVersion, events: [{ name, at, slug?, source?, unit? }] }`.
 * Unknown event names are dropped rather than refused, so a newer app never gets an error from an
 * older server.
 */
export function validateBatch(body: unknown, now = new Date()): BatchResult {
  if (!body || typeof body !== "object") return { ok: false, error: "Send a JSON object." };
  const b = body as Record<string, unknown>;
  if (typeof b.installId !== "string" || !INSTALL_ID.test(b.installId)) return { ok: false, error: "installId is missing or malformed." };
  const platform = b.platform;
  if (typeof platform !== "string" || !["ios", "ipados", "macos", "watchos", "tvos", "clip"].includes(platform)) {
    return { ok: false, error: "platform must be ios, ipados, macos, watchos, tvos or clip." };
  }
  if (typeof b.appVersion !== "string" || !VERSION.test(b.appVersion)) return { ok: false, error: "appVersion is missing or malformed." };
  if (!Array.isArray(b.events)) return { ok: false, error: "events must be an array." };
  if (b.events.length > BATCH_LIMIT) return { ok: false, error: `Send at most ${BATCH_LIMIT} events at a time.` };

  const docs: EventDoc[] = [];
  for (const raw of b.events as unknown[]) {
    if (!raw || typeof raw !== "object") continue;
    const e = raw as Record<string, unknown>;
    if (typeof e.name !== "string" || !(CLIENT_EVENTS as readonly string[]).includes(e.name)) continue;
    const at = typeof e.at === "string" ? new Date(e.at) : new Date(NaN);
    const age = now.getTime() - at.getTime();
    if (Number.isNaN(age) || age > MAX_AGE_MS || age < -MAX_SKEW_MS) continue;
    const doc: EventDoc = {
      name: e.name as EventName, platform: platform as Platform, appVersion: b.appVersion, installId: b.installId,
      at: age < 0 ? now : at,
    };
    if (typeof e.slug === "string" && isSlug(e.slug)) doc.slug = e.slug;
    if (typeof e.source === "string" && SOURCE.test(e.source)) doc.source = e.source;
    if (isUnit(e.unit) && e.unit !== "daysHours") doc.unit = e.unit;
    docs.push(doc);
  }
  return { ok: true, docs, dropped: b.events.length - docs.length };
}
