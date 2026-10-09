import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { Binary, type Collection } from "mongodb";
import { db } from "./mongo.ts";
import type { Kind } from "./time.ts";
import type { Unit } from "./units.ts";
import { makeSlug, type CountdownInput, type PhotoInput } from "./validate.ts";

export interface CountdownDoc {
  slug: string;
  ownerTokenHash: string;
  title: string;
  details: string;
  targetDate: Date;
  createdAt: Date;
  updatedAt: Date;
  publishedAt: Date;
  kind: Kind;
  timeZone: string;
  style: Record<string, unknown>;
  milestones: unknown[];
  hasPhoto: boolean;
  visibility: "link" | "public";
  stats: { views: number; embedViews?: number };
  /**
   * A floating local time ("2027-01-01T00:00:00"): each viewer counts to that moment on their own
   * clock. For these, targetDate holds the same wall-clock time read as UTC and timeZone is "UTC",
   * so the server's dates and sorting work unchanged; only the viewer turns it into a real moment.
   */
  floating?: string;
  /** In the public crypt. */
  curated?: boolean;
  category?: string;
  /** A date pool: people guess when it happens (see pool.ts). */
  pool?: PoolState;
  /** It reached zero and the owner kept it counting up from there ("Married 1 year"). */
  keptCounting?: boolean;
  /** A Host Pass applied to it (see host.ts). */
  host?: { since: Date; environment: string; transactionId: string };
  /** Its custom link, `/c/<alias>`, once a host sets one. The random slug keeps working too. */
  alias?: string;
  /** What it counts in ("sleeps"); missing or "daysHours" is days and hours. */
  unit?: Unit;
  /** Minutes after midnight a sleep starts, for sleeps. */
  bedtime?: number;
}

export interface PoolState {
  closed: boolean;
  /** The real date, once the owner sets it. */
  answer?: Date;
  settledAt?: Date;
}

/** Someone counting down with a shared countdown. No account: just a random key their devices keep. */
interface MemberDoc {
  slug: string;
  memberTokenHash: string;
  joinedAt: Date;
  /** The member's device, for a silent push when the owner edits. */
  pushToken?: string;
  pushSandbox?: boolean;
}

interface PhotoDoc {
  slug: string;
  jpeg: Binary;
  updatedAt: Date;
}

/** What anyone with the link may see. */
export interface PublicCountdown {
  slug: string;
  title: string;
  details: string;
  targetDate: string;
  createdAt: string;
  updatedAt: string;
  kind: Kind;
  timeZone: string;
  style: Record<string, unknown>;
  milestones: unknown[];
  hasPhoto: boolean;
  floating?: string;
  isPublic?: boolean;
  category?: string;
  pool?: { closed: boolean; answer?: string };
  keptCounting?: boolean;
  /** Hosted: custom link, no branding, bigger coffin, keepsake. */
  host?: boolean;
  alias?: string;
  unit?: Unit;
  bedtime?: number;
}

let indexesReady: Promise<unknown> | undefined;

async function collections() {
  const d = await db();
  const countdowns = d.collection<CountdownDoc>("countdowns");
  const photos = d.collection<PhotoDoc>("photos");
  const members = d.collection<MemberDoc>("members");
  indexesReady ??= Promise.all([
    countdowns.createIndex({ slug: 1 }, { unique: true }),
    countdowns.createIndex({ visibility: 1, targetDate: 1 }),
    photos.createIndex({ slug: 1 }, { unique: true }),
    members.createIndex({ slug: 1, memberTokenHash: 1 }, { unique: true }),
  ]);
  await indexesReady;
  return { countdowns, photos, members };
}

export const hashToken = (token: string) => createHash("sha256").update(token).digest("hex");

function tokenMatches(token: string, hash: string): boolean {
  const a = Buffer.from(hashToken(token), "hex");
  const b = Buffer.from(hash, "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}

/** The input with cleared fields (null) left out, so they're unset rather than stored as null. */
function withoutNulls(input: CountdownInput): Omit<CountdownInput, "bedtime"> & { bedtime?: number } {
  const { bedtime, ...rest } = input;
  return typeof bedtime === "number" ? { ...rest, bedtime } : rest;
}

export function toPublic(doc: CountdownDoc): PublicCountdown {
  return {
    slug: doc.slug,
    title: doc.title,
    details: doc.details,
    targetDate: doc.targetDate.toISOString(),
    createdAt: doc.createdAt.toISOString(),
    updatedAt: doc.updatedAt.toISOString(),
    kind: doc.kind,
    timeZone: doc.timeZone,
    style: doc.style,
    milestones: doc.milestones,
    hasPhoto: doc.hasPhoto,
    ...(doc.floating ? { floating: doc.floating } : {}),
    ...(doc.visibility === "public" ? { isPublic: true } : {}),
    ...(doc.category ? { category: doc.category } : {}),
    ...(doc.pool
      ? { pool: { closed: doc.pool.closed, ...(doc.pool.answer ? { answer: doc.pool.answer.toISOString() } : {}) } }
      : {}),
    ...(doc.keptCounting ? { keptCounting: true } : {}),
    ...(doc.host ? { host: true } : {}),
    ...(doc.alias ? { alias: doc.alias } : {}),
    ...(doc.unit && doc.unit !== "daysHours" ? { unit: doc.unit } : {}),
    ...(doc.unit === "sleeps" && doc.bedtime ? { bedtime: doc.bedtime } : {}),
  };
}

async function writePhoto(photos: Collection<PhotoDoc>, slug: string, photo: PhotoInput): Promise<boolean | undefined> {
  if (photo === undefined) return undefined;
  if (photo === null) {
    await photos.deleteOne({ slug });
    return false;
  }
  await photos.updateOne({ slug }, { $set: { jpeg: new Binary(photo), updatedAt: new Date() } }, { upsert: true });
  return true;
}

export async function createCountdown(input: CountdownInput, photo: PhotoInput, pool = false) {
  const { countdowns, photos } = await collections();
  const ownerToken = randomBytes(32).toString("base64url");
  const now = new Date();
  for (let attempt = 0; attempt < 5; attempt++) {
    const slug = makeSlug((n) => randomBytes(n));
    const doc: CountdownDoc = {
      ...withoutNulls(input),
      slug,
      ownerTokenHash: hashToken(ownerToken),
      updatedAt: now,
      publishedAt: now,
      hasPhoto: false,
      visibility: "link",
      stats: { views: 0 },
      ...(pool ? { pool: { closed: false } } : {}),
    };
    try {
      await countdowns.insertOne(doc);
    } catch (e) {
      if ((e as { code?: number }).code === 11000) continue; // slug collision, try another
      throw e;
    }
    if (photo) {
      await writePhoto(photos, slug, photo);
      await countdowns.updateOne({ slug }, { $set: { hasPhoto: true } });
      doc.hasPhoto = true;
    }
    return { doc, ownerToken };
  }
  throw new Error("Could not allocate a unique slug.");
}

export async function getCountdown(slug: string): Promise<CountdownDoc | null> {
  const { countdowns } = await collections();
  return countdowns.findOne({ slug });
}

export async function getPhoto(slug: string): Promise<Buffer | null> {
  const { photos } = await collections();
  const doc = await photos.findOne({ slug });
  return doc ? Buffer.from(doc.jpeg.buffer) : null;
}

export async function recordView(slug: string) {
  const { countdowns } = await collections();
  await countdowns.updateOne({ slug }, { $inc: { "stats.views": 1 } });
}

export async function recordEmbedView(slug: string) {
  const { countdowns } = await collections();
  await countdowns.updateOne({ slug }, { $inc: { "stats.embedViews": 1 } });
}

export type OwnerResult = "ok" | "not-found" | "forbidden";

async function authorize(slug: string, token: string | null): Promise<OwnerResult> {
  const doc = await getCountdown(slug);
  if (!doc) return "not-found";
  return token && tokenMatches(token, doc.ownerTokenHash) ? "ok" : "forbidden";
}

export async function updateCountdown(
  slug: string,
  token: string | null,
  input: CountdownInput,
  photo: PhotoInput,
  /** true turns a date pool on, false turns it off; undefined (older apps) leaves it alone. */
  pool?: boolean,
): Promise<{ result: OwnerResult; doc?: CountdownDoc }> {
  const result = await authorize(slug, token);
  if (result !== "ok") return { result };
  const { countdowns, photos } = await collections();
  const hasPhoto = await writePhoto(photos, slug, photo);
  const current = await getCountdown(slug);
  const kept = current ? keptCountingAfter(current, input) : undefined;
  const update: Record<string, object> = {
    $set: {
      ...withoutNulls(input),
      ...(kept ? { keptCounting: true } : {}),
      updatedAt: new Date(),
      ...(hasPhoto === undefined ? {} : { hasPhoto }),
      ...(pool === true && !current?.pool ? { pool: { closed: false } } : {}),
    },
  };
  // A settled pool stays: its result is history now.
  if (pool === false && current?.pool && !current.pool.answer) update.$unset = { pool: "" };
  if (kept === false) update.$unset = { ...(update.$unset ?? {}), keptCounting: "" };
  if (input.bedtime === null) update.$unset = { ...(update.$unset ?? {}), bedtime: "" };
  const doc = await countdowns.findOneAndUpdate({ slug }, update, { returnDocument: "after" });
  return { result, doc: doc ?? undefined };
}

/**
 * Whether an edit keeps a finished countdown counting up from its zero: true when a countdown that
 * has passed turns into a count-up from the same moment, false when a kept one turns back, and
 * undefined when nothing about that changes. Pure, for tests.
 */
export function keptCountingAfter(
  current: Pick<CountdownDoc, "kind" | "targetDate" | "keptCounting">,
  input: Pick<CountdownInput, "kind" | "targetDate">,
  now = new Date(),
): boolean | undefined {
  if (current.keptCounting) return input.kind === "countUp" ? undefined : false;
  const finished = current.kind !== "countUp" && current.targetDate.getTime() <= now.getTime();
  if (finished && input.kind === "countUp" && input.targetDate.getTime() === current.targetDate.getTime()) return true;
  return undefined;
}

export async function deleteCountdown(slug: string, token: string | null): Promise<OwnerResult> {
  const result = await authorize(slug, token);
  if (result !== "ok") return result;
  const { countdowns, photos, members } = await collections();
  await Promise.all([countdowns.deleteOne({ slug }), photos.deleteOne({ slug }), members.deleteMany({ slug })]);
  return "ok";
}

// MARK: - Members

export async function memberCount(slug: string): Promise<number> {
  const { members } = await collections();
  return members.countDocuments({ slug });
}

/** Adds a member and returns the key their devices use to leave. null if the countdown is gone. */
export async function joinCountdown(slug: string): Promise<{ memberToken: string; memberCount: number } | null> {
  const { members } = await collections();
  if (!(await getCountdown(slug))) return null;
  const memberToken = randomBytes(32).toString("base64url");
  await members.insertOne({ slug, memberTokenHash: hashToken(memberToken), joinedAt: new Date() });
  return { memberToken, memberCount: await memberCount(slug) };
}

/** Records where to push this member. False if the member key isn't a member of this countdown. */
export async function setMemberPushToken(slug: string, memberToken: string | null, pushToken: string, sandbox: boolean) {
  if (!memberToken) return false;
  const { members } = await collections();
  const result = await members.updateOne(
    { slug, memberTokenHash: hashToken(memberToken) },
    { $set: { pushToken, pushSandbox: sandbox } },
  );
  return result.matchedCount > 0;
}

/** Every device to wake when this countdown changes. */
export async function pushTargets(slug: string): Promise<{ token: string; sandbox: boolean }[]> {
  const { members } = await collections();
  const docs = await members.find({ slug, pushToken: { $exists: true } }, { projection: { pushToken: 1, pushSandbox: 1 } }).toArray();
  return docs.map((d) => ({ token: d.pushToken!, sandbox: d.pushSandbox ?? false }));
}

/** Drops device tokens APNs says are no longer valid (the app was deleted). */
export async function forgetPushTokens(tokens: string[]) {
  if (tokens.length === 0) return;
  const { members } = await collections();
  await members.updateMany({ pushToken: { $in: tokens } }, { $unset: { pushToken: "", pushSandbox: "" } });
}

/** Removes a member. Leaving twice, or leaving a countdown that's gone, is fine. */
export async function leaveCountdown(slug: string, token: string | null): Promise<void> {
  if (!token) return;
  const { members } = await collections();
  await members.deleteOne({ slug, memberTokenHash: hashToken(token) });
}
