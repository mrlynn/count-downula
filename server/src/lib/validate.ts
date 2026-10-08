// Pure validation for publish and update requests, kept free of server imports so it's easy to test.
import type { Kind } from "./time.ts";

export const LIMITS = {
  title: 120,
  details: 1_000,
  styleBytes: 8_192,
  milestonesBytes: 16_384,
  milestones: 50,
  photoBytes: 400 * 1024,
};

export interface CountdownInput {
  title: string;
  details: string;
  targetDate: Date;
  createdAt: Date;
  kind: Kind;
  timeZone: string;
  style: Record<string, unknown>;
  milestones: unknown[];
}

/** undefined: leave the photo alone. null: remove it. Buffer: replace it. */
export type PhotoInput = Buffer | null | undefined;

export type Result<T> = { ok: true; value: T } | { ok: false; error: string };

const KINDS: Kind[] = ["event", "timer", "countUp"];

function parseDate(v: unknown): Date | null {
  if (typeof v !== "string" && typeof v !== "number") return null;
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
}

function validTimeZone(tz: unknown): string {
  if (typeof tz !== "string" || tz.length > 64) return "UTC";
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
    return tz;
  } catch {
    return "UTC";
  }
}

export function validateCountdown(body: unknown): Result<CountdownInput> {
  if (!body || typeof body !== "object") return { ok: false, error: "Expected a JSON object." };
  const b = body as Record<string, unknown>;

  const title = typeof b.title === "string" ? b.title.trim() : "";
  if (!title) return { ok: false, error: "A title is required." };
  if (title.length > LIMITS.title) return { ok: false, error: `Titles are limited to ${LIMITS.title} characters.` };

  const details = typeof b.details === "string" ? b.details.trim() : "";
  if (details.length > LIMITS.details) {
    return { ok: false, error: `Descriptions are limited to ${LIMITS.details} characters.` };
  }

  const targetDate = parseDate(b.targetDate);
  if (!targetDate) return { ok: false, error: "targetDate must be an ISO 8601 date." };
  const createdAt = parseDate(b.createdAt) ?? new Date();

  const kind = (KINDS as unknown[]).includes(b.kind) ? (b.kind as Kind) : "event";

  const style = b.style && typeof b.style === "object" && !Array.isArray(b.style) ? (b.style as Record<string, unknown>) : {};
  if (JSON.stringify(style).length > LIMITS.styleBytes) return { ok: false, error: "Style is too large." };

  const milestones = Array.isArray(b.milestones) ? b.milestones : [];
  if (milestones.length > LIMITS.milestones || JSON.stringify(milestones).length > LIMITS.milestonesBytes) {
    return { ok: false, error: "Too many milestones." };
  }

  return {
    ok: true,
    value: { title, details, targetDate, createdAt, kind, timeZone: validTimeZone(b.timeZone), style, milestones },
  };
}

export function validatePhoto(v: unknown): Result<PhotoInput> {
  if (v === undefined) return { ok: true, value: undefined };
  if (v === null) return { ok: true, value: null };
  if (typeof v !== "string") return { ok: false, error: "photo must be base64 JPEG data or null." };
  const data = Buffer.from(v, "base64");
  if (data.length === 0) return { ok: false, error: "photo is empty." };
  if (data.length > LIMITS.photoBytes) return { ok: false, error: "photo is larger than 400 KB." };
  if (data[0] !== 0xff || data[1] !== 0xd8 || data[2] !== 0xff) return { ok: false, error: "photo must be a JPEG." };
  return { ok: true, value: data };
}

const SLUG_ALPHABET = "23456789abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";

/** 8 characters with no look-alikes (0/O, 1/l/I). About 46 bits, so links can't be guessed. */
export function makeSlug(random: (n: number) => Uint8Array): string {
  const bytes = random(8);
  return Array.from(bytes, (b) => SLUG_ALPHABET[b % SLUG_ALPHABET.length]).join("");
}

export function isSlug(s: string): boolean {
  return /^[a-zA-Z0-9-]{4,40}$/.test(s);
}
