// The public crypt: curated countdowns anyone can browse and join. Entries are loaded by an admin
// (PUT /api/admin/crypt); joining one is the same as joining any shared countdown.
import { randomBytes } from "node:crypto";
import { db } from "./mongo.ts";
import { hashToken, type CountdownDoc, toPublic, type PublicCountdown } from "./countdowns.ts";
import { SCENE_IDS } from "./style.ts";

export const CATEGORIES = [
  { slug: "holidays", name: "Holidays" },
  { slug: "sky", name: "Sky" },
  { slug: "sports", name: "Sports" },
  { slug: "fun", name: "Fun days" },
] as const;

export type CategorySlug = (typeof CATEGORIES)[number]["slug"];

/** "2027-01-01T00:00:00" read as UTC, the convention for floating countdowns on the server. */
export function floatingAsUTC(local: string): Date {
  return new Date(`${local}Z`);
}

/** Still worth showing: not yet past, or past within a day. Floating times get the widest zone spread. */
export function isCurrent(doc: Pick<CountdownDoc, "targetDate" | "floating">, now = new Date()): boolean {
  // A floating midnight reaches the last time zones (UTC-12) 12 hours after it reaches UTC.
  const lastMoment = doc.targetDate.getTime() + (doc.floating ? 12 * 3_600_000 : 0);
  return lastMoment + 24 * 3_600_000 > now.getTime();
}

export interface CryptEntry {
  countdown: PublicCountdown;
  memberCount: number;
}

export async function listCrypt(category?: string, now = new Date()): Promise<CryptEntry[]> {
  const d = await db();
  const docs = await d.collection<CountdownDoc>("countdowns")
    .find({ visibility: "public", curated: true, ...(category ? { category } : {}) })
    .sort({ targetDate: 1 })
    .toArray();
  const current = docs.filter((doc) => isCurrent(doc, now));
  const counts = await d.collection("members")
    .aggregate<{ _id: string; n: number }>([
      { $match: { slug: { $in: current.map((c) => c.slug) } } },
      { $group: { _id: "$slug", n: { $sum: 1 } } },
    ])
    .toArray();
  const bySlug = new Map(counts.map((c) => [c._id, c.n]));
  return current.map((doc) => ({ countdown: toPublic(doc), memberCount: bySlug.get(doc.slug) ?? 0 }));
}

// MARK: - Admin

export interface CryptInput {
  slug: string;
  title: string;
  details: string;
  category: CategorySlug;
  scene: string;
  /** Floating local time, "YYYY-MM-DDTHH:mm:ss". */
  local?: string;
  /** Exact moment, ISO 8601 with Z or an offset. */
  at?: string;
}


/** Checks one admin entry. Pure, for tests. */
export function validateCryptEntry(raw: unknown): { ok: true; value: CryptInput } | { ok: false; error: string } {
  const e = (raw ?? {}) as Record<string, unknown>;
  const str = (k: string) => (typeof e[k] === "string" ? (e[k] as string).trim() : "");
  const slug = str("slug");
  if (!/^[a-z0-9-]{4,40}$/.test(slug)) return { ok: false, error: `bad slug: ${slug}` };
  if (!str("title") || str("title").length > 120) return { ok: false, error: `${slug}: title` };
  if (!CATEGORIES.some((c) => c.slug === e.category)) return { ok: false, error: `${slug}: category` };
  if (!SCENE_IDS.includes(str("scene"))) return { ok: false, error: `${slug}: scene` };
  const local = str("local");
  const at = str("at");
  if (!!local === !!at) return { ok: false, error: `${slug}: give exactly one of local or at` };
  if (local && (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$/.test(local) || isNaN(floatingAsUTC(local).getTime()))) {
    return { ok: false, error: `${slug}: local must be YYYY-MM-DDTHH:mm:ss` };
  }
  if (at && (!/(Z|[+-]\d{2}:\d{2})$/.test(at) || isNaN(new Date(at).getTime()))) {
    return { ok: false, error: `${slug}: at needs a Z or offset` };
  }
  return {
    ok: true,
    value: { slug, title: str("title"), details: str("details").slice(0, 1_000), category: e.category as CategorySlug,
      scene: str("scene"), ...(local ? { local } : { at }) },
  };
}

/** Creates or updates curated entries by slug. Their owner key is random and thrown away. */
export async function upsertCrypt(entries: CryptInput[]) {
  const countdowns = (await db()).collection<CountdownDoc>("countdowns");
  const now = new Date();
  for (const e of entries) {
    const targetDate = e.local ? floatingAsUTC(e.local) : new Date(e.at!);
    await countdowns.updateOne(
      { slug: e.slug },
      {
        $set: {
          title: e.title, details: e.details, targetDate, kind: "event", timeZone: "UTC",
          style: { background: { scene: { _0: e.scene } }, font: "serif", weight: "bold" },
          milestones: [], visibility: "public", curated: true, category: e.category, updatedAt: now,
          ...(e.local ? { floating: e.local } : {}),
        },
        ...(e.local ? {} : { $unset: { floating: "" } }),
        $setOnInsert: {
          slug: e.slug, ownerTokenHash: hashToken(randomBytes(32).toString("base64url")),
          createdAt: new Date(now.getTime() - 86_400_000), publishedAt: now, hasPhoto: false, stats: { views: 0 },
        },
      },
      { upsert: true },
    );
  }
}
