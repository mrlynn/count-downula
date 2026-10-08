import { createHash } from "node:crypto";
import type { Collection } from "mongodb";
import { db } from "./mongo.ts";

/**
 * Fixed-window counters in MongoDB. Serverless instances share nothing in memory, but they all
 * share the database, so the counts hold across every instance. Expired windows are removed by
 * a TTL index.
 */
export interface Limit {
  name: string;
  max: number;
  windowSeconds: number;
}

/** Tuned for people, not scripts: one person publishes a few countdowns, not dozens. */
export const limits = {
  publishPerHour: { name: "publish-hour", max: 10, windowSeconds: 3_600 },
  publishPerDay: { name: "publish-day", max: 30, windowSeconds: 86_400 },
  /** A ceiling on everyone together, so a botnet can't fill the database overnight. */
  publishAllPerHour: { name: "publish-all", max: 2_000, windowSeconds: 3_600 },
  /** The app pushes the whole countdown after every edit and each yearly or sunrise roll. */
  editsPerHour: { name: "edit-hour", max: 120, windowSeconds: 3_600 },
  editsPerCountdownPerHour: { name: "edit-slug", max: 60, windowSeconds: 3_600 },
  deletesPerHour: { name: "delete-hour", max: 60, windowSeconds: 3_600 },
} satisfies Record<string, Limit>;

export interface Window {
  key: string;
  resetsAt: Date;
}

/** The counter a request lands in: one per limit, subject and window. */
export function windowFor(limit: Limit, subject: string, now: Date): Window {
  const seconds = Math.floor(now.getTime() / 1000);
  const start = seconds - (seconds % limit.windowSeconds);
  return {
    key: `${limit.name}:${subject}:${start}`,
    resetsAt: new Date((start + limit.windowSeconds) * 1000),
  };
}

/**
 * Who's asking. Vercel sets `x-forwarded-for` itself (clients can't spoof the first entry there)
 * and `x-real-ip`. The address is hashed before it's stored, and the counter expires with its
 * window, so no IP addresses are kept.
 */
export function clientSubject(request: Request): string {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  const ip = forwarded || request.headers.get("x-real-ip")?.trim() || "unknown";
  const salt = process.env.RATE_LIMIT_SALT ?? "countdownula";
  return createHash("sha256").update(`${salt}:${ip}`).digest("base64url").slice(0, 22);
}

interface CounterDoc {
  _id: string;
  count: number;
  expiresAt: Date;
}

let indexReady: Promise<unknown> | undefined;

async function counters(): Promise<Collection<CounterDoc>> {
  const collection = (await db()).collection<CounterDoc>("rateLimits");
  indexReady ??= collection.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });
  await indexReady;
  return collection;
}

async function increment(window: Window): Promise<number> {
  const collection = await counters();
  for (let attempt = 0; ; attempt++) {
    try {
      const doc = await collection.findOneAndUpdate(
        { _id: window.key },
        { $inc: { count: 1 }, $setOnInsert: { expiresAt: window.resetsAt } },
        { upsert: true, returnDocument: "after" },
      );
      return doc?.count ?? 1;
    } catch (error) {
      // Two first requests in the same window can race to insert; the loser retries and increments.
      if ((error as { code?: number }).code === 11000 && attempt === 0) continue;
      throw error;
    }
  }
}

/** "a minute", "12 minutes", "3 hours". */
export function waitText(seconds: number): string {
  if (seconds <= 60) return "a minute";
  if (seconds < 3_600) return `${Math.ceil(seconds / 60)} minutes`;
  const hours = Math.ceil(seconds / 3_600);
  return hours === 1 ? "an hour" : `${hours} hours`;
}

export type Verdict = { ok: true } | { ok: false; retryAfter: number; limit: Limit };

/**
 * Counts this request against every limit given and refuses it if any is over. Every counter is
 * bumped, even after one trips, so hammering a closed door keeps it closed.
 */
export async function checkLimits(checks: [Limit, string][], now = new Date()): Promise<Verdict> {
  const results = await Promise.all(
    checks.map(async ([limit, subject]) => {
      const window = windowFor(limit, subject, now);
      return { limit, window, count: await increment(window) };
    }),
  );
  const over = results
    .filter((r) => r.count > r.limit.max)
    .sort((a, b) => b.window.resetsAt.getTime() - a.window.resetsAt.getTime())[0];
  if (!over) return { ok: true };
  const retryAfter = Math.max(1, Math.ceil((over.window.resetsAt.getTime() - now.getTime()) / 1000));
  return { ok: false, retryAfter, limit: over.limit };
}
