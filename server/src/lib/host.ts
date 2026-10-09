// The host tier: a Host Pass bought in the app and applied to one shared countdown. It unlocks a
// custom link, a page and embeds without Count Downcula's branding, a bigger coffin (several photos
// and a short video per note) and the keepsake export.
import { db } from "./mongo.ts";
import type { SignedTransaction } from "./storekit.ts";

interface HostPassDoc {
  transactionId: string;
  originalTransactionId: string;
  slug: string;
  environment: string;
  purchasedAt: Date;
  appliedAt: Date;
}

interface AliasDoc {
  alias: string;
  slug: string;
  createdAt: Date;
}

let indexesReady: Promise<unknown> | undefined;

async function collections() {
  const d = await db();
  const passes = d.collection<HostPassDoc>("hostPasses");
  const aliases = d.collection<AliasDoc>("aliases");
  indexesReady ??= Promise.all([
    passes.createIndex({ transactionId: 1 }, { unique: true }),
    aliases.createIndex({ alias: 1 }, { unique: true }),
    aliases.createIndex({ slug: 1 }),
  ]);
  await indexesReady;
  return { passes, aliases, countdowns: d.collection("countdowns") };
}

export type HostResult = "applied" | "already" | "used-elsewhere";

/**
 * Attaches a verified Host Pass to a countdown. A transaction counts once: sending it again for the
 * same countdown is fine (a retry), for another one is refused.
 */
export async function applyHostPass(slug: string, transaction: SignedTransaction, now = new Date()): Promise<HostResult> {
  const { passes, countdowns } = await collections();
  try {
    await passes.insertOne({
      transactionId: transaction.transactionId, originalTransactionId: transaction.originalTransactionId, slug,
      environment: transaction.environment, purchasedAt: new Date(transaction.purchaseDate), appliedAt: now,
    });
  } catch (error) {
    if ((error as { code?: number }).code !== 11000) throw error;
    const existing = await passes.findOne({ transactionId: transaction.transactionId });
    return existing?.slug === slug ? "already" : "used-elsewhere";
  }
  await countdowns.updateOne(
    { slug },
    { $set: { host: { since: now, environment: transaction.environment, transactionId: transaction.transactionId } } },
  );
  return "applied";
}

// MARK: - Custom links

/** Words a custom link can't be, so they never shadow a route or look official. */
const RESERVED = new Set([
  "admin", "api", "app", "c", "crypt", "embed", "help", "new", "support", "www", "countdowncula", "countdownula",
  "count-downcula", "privacy", "terms", "login", "signin", "settings", "official", "apple", "test",
]);

export const ALIAS_PATTERN = /^[a-z0-9](?:[a-z0-9-]{1,38})[a-z0-9]$/;

/** Checks and normalizes a requested custom link. Pure, for tests. */
export function validateAlias(input: unknown): { ok: true; value: string } | { ok: false; error: string } {
  if (typeof input !== "string") return { ok: false, error: "Send the link you'd like as alias." };
  const alias = input.trim().toLowerCase().replace(/\s+/g, "-");
  if (!ALIAS_PATTERN.test(alias)) {
    return { ok: false, error: "Use 3 to 40 lowercase letters, numbers and hyphens, starting and ending with a letter or number." };
  }
  if (alias.includes("--")) return { ok: false, error: "Use one hyphen at a time." };
  if (RESERVED.has(alias)) return { ok: false, error: "That link is reserved. Try another." };
  return { ok: true, value: alias };
}

export type AliasResult = { ok: true; alias: string } | { ok: false; error: string };

/**
 * Gives a hosted countdown a custom link. Earlier links it had keep working; a link another
 * countdown has, or a countdown's own code, can't be taken.
 */
export async function setAlias(slug: string, alias: string, now = new Date()): Promise<AliasResult> {
  const { aliases, countdowns } = await collections();
  if (await countdowns.findOne({ slug: alias })) return { ok: false, error: "That link is taken. Try another." };
  const existing = await aliases.findOne({ alias });
  if (existing && existing.slug !== slug) return { ok: false, error: "That link is taken. Try another." };
  if (!existing) {
    try {
      await aliases.insertOne({ alias, slug, createdAt: now });
    } catch (error) {
      if ((error as { code?: number }).code === 11000) return { ok: false, error: "That link is taken. Try another." };
      throw error;
    }
  }
  await countdowns.updateOne({ slug }, { $set: { alias } });
  forgetCached(alias);
  return { ok: true, alias };
}

/** Frees a countdown's custom links when it stops being shared. */
export async function purgeAliases(slug: string) {
  const { aliases } = await collections();
  const gone = await aliases.find({ slug }).toArray();
  await aliases.deleteMany({ slug });
  for (const a of gone) forgetCached(a.alias);
}

// Lookups from the proxy happen on every page and API request with a lowercase segment, so they're
// cached briefly in memory (Fluid Compute reuses instances). Misses are cached too.
const cache = new Map<string, { slug: string | null; until: number }>();
const CACHE_MS = 60_000;

function forgetCached(alias: string) {
  cache.delete(alias);
}

/** The countdown a custom link points to, or null. */
export async function resolveAlias(alias: string, now = Date.now()): Promise<string | null> {
  if (!ALIAS_PATTERN.test(alias)) return null;
  const hit = cache.get(alias);
  if (hit && hit.until > now) return hit.slug;
  const { aliases } = await collections();
  const slug = (await aliases.findOne({ alias }))?.slug ?? null;
  cache.set(alias, { slug, until: now + CACHE_MS });
  if (cache.size > 5_000) cache.delete(cache.keys().next().value!);
  return slug;
}
