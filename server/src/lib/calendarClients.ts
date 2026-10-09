import type { Collection } from "mongodb";
import { logEvent } from "./events.ts";
import { db } from "./mongo.ts";
import { clientSubject } from "./rateLimit.ts";

/**
 * Who's polling a calendar feed, so the dashboard can count subscriptions rather than fetches.
 * A client is the same salted address hash the rate limits use, never the address itself, and is
 * forgotten 45 days after its last fetch. Google fetches for many people from shared addresses,
 * so this undercounts Google subscribers.
 */
interface CalendarClientDoc {
  slug: string;
  client: string;
  app: string;
  lastSeen: Date;
}

let indexesReady: Promise<unknown> | undefined;

async function clients(): Promise<Collection<CalendarClientDoc>> {
  const collection = (await db()).collection<CalendarClientDoc>("calendarClients");
  indexesReady ??= Promise.all([
    collection.createIndex({ slug: 1, client: 1 }, { unique: true }),
    collection.createIndex({ lastSeen: 1 }, { expireAfterSeconds: 45 * 86_400 }),
  ]);
  await indexesReady;
  return collection;
}

/** Which calendar app is asking, from its user agent. */
export function calendarApp(userAgent: string): string {
  if (/google/i.test(userAgent)) return "google";
  if (/microsoft|outlook/i.test(userAgent)) return "outlook";
  if (/dataaccessd|CalendarAgent|iCal|macOS|iOS/i.test(userAgent)) return "apple";
  if (/Mozilla\//.test(userAgent)) return "browser";
  return "other";
}

export async function noteCalendarClient(slug: string, request: Request) {
  const app = calendarApp(request.headers.get("user-agent") ?? "");
  const result = await (await clients()).updateOne(
    { slug, client: clientSubject(request) },
    { $set: { lastSeen: new Date(), app } },
    { upsert: true },
  );
  // A first fetch from a client is a new subscription (or a one-off download, from a browser).
  if (result.upsertedCount) await logEvent("calendar_subscribed", null, { slug, source: app });
}
