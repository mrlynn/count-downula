import { createHash, randomBytes, timingSafeEqual } from "node:crypto";
import { Binary, type Collection } from "mongodb";
import { db } from "./mongo.ts";
import type { Kind } from "./time.ts";
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
  stats: { views: number };
}

/** Someone counting down with a shared countdown. No account: just a random key their devices keep. */
interface MemberDoc {
  slug: string;
  memberTokenHash: string;
  joinedAt: Date;
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

export async function createCountdown(input: CountdownInput, photo: PhotoInput) {
  const { countdowns, photos } = await collections();
  const ownerToken = randomBytes(32).toString("base64url");
  const now = new Date();
  for (let attempt = 0; attempt < 5; attempt++) {
    const slug = makeSlug((n) => randomBytes(n));
    const doc: CountdownDoc = {
      ...input,
      slug,
      ownerTokenHash: hashToken(ownerToken),
      updatedAt: now,
      publishedAt: now,
      hasPhoto: false,
      visibility: "link",
      stats: { views: 0 },
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
): Promise<{ result: OwnerResult; doc?: CountdownDoc }> {
  const result = await authorize(slug, token);
  if (result !== "ok") return { result };
  const { countdowns, photos } = await collections();
  const hasPhoto = await writePhoto(photos, slug, photo);
  const doc = await countdowns.findOneAndUpdate(
    { slug },
    { $set: { ...input, updatedAt: new Date(), ...(hasPhoto === undefined ? {} : { hasPhoto }) } },
    { returnDocument: "after" },
  );
  return { result, doc: doc ?? undefined };
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

/** Removes a member. Leaving twice, or leaving a countdown that's gone, is fine. */
export async function leaveCountdown(slug: string, token: string | null): Promise<void> {
  if (!token) return;
  const { members } = await collections();
  await members.deleteOne({ slug, memberTokenHash: hashToken(token) });
}
