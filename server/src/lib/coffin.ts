// The sealed coffin: notes and photos people drop into a shared countdown, kept sealed until zero.
// The server is the lock: nothing but a count leaves here before the countdown's target date.
import { createHmac, timingSafeEqual } from "node:crypto";
import { del } from "@vercel/blob";
import { ObjectId, type Collection } from "mongodb";
import { getCountdown, hashToken, type CountdownDoc } from "./countdowns.ts";
import { db } from "./mongo.ts";

export const COFFIN_LIMITS = {
  name: 40,
  text: 500,
  photoBytes: 400 * 1024,
  /** Contributions per countdown, so one link can't fill the store. */
  perCountdown: 500,
};

export interface ContributionDoc {
  _id: ObjectId;
  slug: string;
  authorTokenHash: string;
  name: string;
  text: string;
  /** Pathname in the private Blob store, when there's a photo. */
  photoPath?: string;
  createdAt: Date;
  removedAt?: Date;
  reports: number;
}

/** What a contribution looks like to the app. */
export interface PublicContribution {
  id: string;
  name: string;
  text: string;
  hasPhoto: boolean;
  createdAt: string;
  mine: boolean;
}

export type Role = "owner" | "member";

let indexesReady: Promise<unknown> | undefined;

export async function contributions(): Promise<Collection<ContributionDoc>> {
  const collection = (await db()).collection<ContributionDoc>("contributions");
  indexesReady ??= collection.createIndex({ slug: 1, createdAt: 1 });
  await indexesReady;
  return collection;
}

/** Who's asking: the countdown's owner, one of its members, or nobody we know. */
export async function roleFor(doc: CountdownDoc, token: string | null): Promise<Role | null> {
  if (!token) return null;
  const hash = hashToken(token);
  if (hash === doc.ownerTokenHash) return "owner";
  const member = await (await db()).collection("members").findOne({ slug: doc.slug, memberTokenHash: hash });
  return member ? "member" : null;
}

export function isOpen(doc: Pick<CountdownDoc, "targetDate">, now = new Date()): boolean {
  return now >= doc.targetDate;
}

export function toPublic(c: ContributionDoc, viewerHash: string | null): PublicContribution {
  return {
    id: c._id.toHexString(),
    name: c.name,
    text: c.text,
    hasPhoto: Boolean(c.photoPath),
    createdAt: c.createdAt.toISOString(),
    mine: viewerHash === c.authorTokenHash,
  };
}

export interface ContributionInput {
  name: string;
  text: string;
  photo: Buffer | null;
}

/** Checks a contribution request body. Pure, so it's easy to test. */
export function validateContribution(body: unknown): { ok: true; value: ContributionInput } | { ok: false; error: string } {
  if (!body || typeof body !== "object") return { ok: false, error: "Send a JSON body." };
  const b = body as Record<string, unknown>;
  const name = typeof b.name === "string" ? b.name.trim() : "";
  const text = typeof b.text === "string" ? b.text.trim() : "";
  if (!name) return { ok: false, error: "Add your name so people know who it's from." };
  if (name.length > COFFIN_LIMITS.name) return { ok: false, error: `Names are limited to ${COFFIN_LIMITS.name} characters.` };
  if (text.length > COFFIN_LIMITS.text) return { ok: false, error: `Notes are limited to ${COFFIN_LIMITS.text} characters.` };
  let photo: Buffer | null = null;
  if (b.photo != null) {
    if (typeof b.photo !== "string") return { ok: false, error: "photo must be a base64 JPEG." };
    photo = Buffer.from(b.photo, "base64");
    if (photo.length > COFFIN_LIMITS.photoBytes) return { ok: false, error: "That photo is too large." };
    if (photo[0] !== 0xff || photo[1] !== 0xd8) return { ok: false, error: "Photos must be JPEG." };
  }
  if (!text && !photo) return { ok: false, error: "Write a note or add a photo." };
  return { ok: true, value: { name, text, photo } };
}

// MARK: - Report links

/**
 * A report email links to a page that removes the contribution. The link carries an HMAC of the
 * contribution ID so only someone with the email can use it; the page still asks before removing.
 */
export function reportSignature(id: string, secret = process.env.ADMIN_SECRET ?? ""): string {
  return createHmac("sha256", secret).update(`coffin-remove:${id}`).digest("base64url");
}

export function reportSignatureValid(id: string, signature: string, secret = process.env.ADMIN_SECRET ?? ""): boolean {
  if (!secret) return false;
  const a = Buffer.from(reportSignature(id, secret));
  const b = Buffer.from(signature);
  return a.length === b.length && timingSafeEqual(a, b);
}

export async function loadCountdownAndRole(slug: string, token: string | null) {
  const doc = await getCountdown(slug);
  return { doc, role: doc ? await roleFor(doc, token) : null };
}

export function parseId(id: string): ObjectId | null {
  return ObjectId.isValid(id) && /^[0-9a-f]{24}$/i.test(id) ? new ObjectId(id) : null;
}

/** Deletes a countdown's whole coffin, photos included. Used when the owner stops sharing. */
export async function purgeCoffin(slug: string) {
  const collection = await contributions();
  const paths = (await collection.find({ slug, photoPath: { $exists: true } }).toArray()).map((c) => c.photoPath!);
  if (paths.length) await del(paths).catch(() => {});
  await collection.deleteMany({ slug });
}

export async function sealedCount(slug: string): Promise<number> {
  return (await contributions()).countDocuments({ slug, removedAt: { $exists: false } });
}
