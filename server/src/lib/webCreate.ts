// Making and editing a countdown on the web (5.3, web create): the choices the editor offers and
// the payload it sends to the same publish API the app uses. The browser keeps the owner token;
// an emailed edit link carries it to another browser. Pure, for tests.
import type { Kind } from "./time.ts";
import type { Unit } from "./units.ts";

type RGBA = { red: number; green: number; blue: number };

const hex = (n: number): RGBA => ({
  red: ((n >> 16) & 0xff) / 255,
  green: ((n >> 8) & 0xff) / 255,
  blue: (n & 0xff) / 255,
});

/** Scenes with a pre-rendered image, occasions first, as in the app's style editor. */
export const WEB_SCENES = [
  "birthday", "wedding", "baby", "graduation", "hearts", "fireworks", "airplane", "beach", "stadium", "campfire",
  "midnight", "starfield", "aurora", "sunset", "mountains", "ocean", "snowfall", "blossoms", "city", "confetti",
  "balloons", "harvestMoon",
] as const;

/** The app's gradient presets (GradientSpec.presets), so a web-made countdown looks the same in the app. */
export const WEB_GRADIENTS: { id: string; stops: number[]; angle: number }[] = [
  { id: "night", stops: [0x4d0a1f, 0x0f050d], angle: 45 },
  { id: "ember", stops: [0xf83600, 0x6a0d1b], angle: 120 },
  { id: "sunset", stops: [0xff9a5a, 0xe94e77, 0x4b2a6b], angle: 90 },
  { id: "candy", stops: [0xff6fd8, 0x3813c2], angle: 135 },
  { id: "ocean", stops: [0x2bc0e4, 0x1a3d7c], angle: 90 },
  { id: "aurora", stops: [0x43e97b, 0x1e6f8a, 0x14213d], angle: 70 },
  { id: "forest", stops: [0x5a8f3c, 0x173b2a], angle: 110 },
  { id: "graphite", stops: [0x5c6370, 0x16181d], angle: 135 },
];

export type Look = { scene: string } | { gradient: string } | { photo: true };

/** The app's CountdownStyle JSON (Swift Codable: enums with values as {"case":{"_0":value}}). */
export function styleFor(look: Look): Record<string, unknown> {
  if ("photo" in look) return { background: { photo: {} }, font: "rounded", weight: "bold" };
  if ("scene" in look) {
    const scene = (WEB_SCENES as readonly string[]).includes(look.scene) ? look.scene : "midnight";
    return { background: { scene: { _0: scene } }, font: "rounded", weight: "bold" };
  }
  const preset = WEB_GRADIENTS.find((g) => g.id === look.gradient) ?? WEB_GRADIENTS[0];
  return { background: { gradient: { _0: { stops: preset.stops.map(hex), angle: preset.angle } } }, font: "rounded", weight: "bold" };
}

/** Reads a stored style back as one of the editor's choices, for editing. */
export function lookOf(style: unknown): Look {
  const bg = (style as { background?: Record<string, { _0?: unknown }> } | null)?.background ?? {};
  const kind = Object.keys(bg)[0];
  if (kind === "photo" || kind === "automatic") return { photo: true };
  if (kind === "scene" && typeof bg.scene?._0 === "string") return { scene: bg.scene._0 };
  if (kind === "gradient") {
    const stops = (bg.gradient?._0 as { stops?: RGBA[] } | undefined)?.stops ?? [];
    const first = stops[0];
    const match = first && WEB_GRADIENTS.find((g) => {
      const c = hex(g.stops[0]);
      return Math.abs(c.red - first.red) < 0.01 && Math.abs(c.green - first.green) < 0.01 && Math.abs(c.blue - first.blue) < 0.01;
    });
    return { gradient: match ? match.id : WEB_GRADIENTS[0].id };
  }
  return { scene: "midnight" };
}

/**
 * The moment a wall-clock date and time ("2026-12-31", "23:59") happens in a time zone. Works
 * without a date library by asking Intl what that zone reads at a first guess, and correcting.
 */
export function zonedTime(date: string, time: string, timeZone: string): Date | null {
  const d = /^(\d{4})-(\d{2})-(\d{2})$/.exec(date);
  const t = /^(\d{2}):(\d{2})$/.exec(time || "00:00");
  if (!d || !t) return null;
  const wanted = Date.UTC(+d[1], +d[2] - 1, +d[3], +t[1], +t[2]);
  let zone = timeZone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const read = (ms: number) => {
    const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
      timeZone: zone, year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric", hourCycle: "h23",
    }).formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
    return Date.UTC(+p.year, +p.month - 1, +p.day, +p.hour, +p.minute);
  };
  // Twice, so a guess on the wrong side of a daylight saving change settles.
  let guess = wanted - (read(wanted) - wanted);
  guess = guess - (read(guess) - wanted);
  return new Date(guess);
}

/** The wall-clock date and time a moment reads in a zone: the editor's fields when editing. */
export function zonedFields(moment: Date, timeZone: string): { date: string; time: string } {
  let zone = timeZone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
    timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", hourCycle: "h23",
  }).formatToParts(moment).map((x) => [x.type, x.value]));
  return { date: `${p.year}-${p.month}-${p.day}`, time: `${p.hour}:${p.minute}` };
}

export interface WebForm {
  title: string;
  details: string;
  date: string;
  time: string;
  timeZone: string;
  look: Look;
  unit: Unit;
}

export type FormError = "title" | "date" | "past";

/** The publish/update body's countdown, or what's wrong with the form. */
export function countdownPayload(
  form: WebForm,
  now = new Date(),
  createdAt?: string,
): { ok: true; countdown: Record<string, unknown> } | { ok: false; error: FormError } {
  const title = form.title.trim();
  if (!title) return { ok: false, error: "title" };
  const target = zonedTime(form.date, form.time, form.timeZone);
  if (!target) return { ok: false, error: "date" };
  if (target <= now) return { ok: false, error: "past" };
  const kind: Kind = "event";
  return {
    ok: true,
    countdown: {
      title: title.slice(0, 120),
      details: form.details.trim().slice(0, 1_000),
      targetDate: target.toISOString(),
      createdAt: createdAt ?? now.toISOString(),
      kind,
      timeZone: form.timeZone,
      style: styleFor(form.look),
      milestones: [],
      pool: false,
      unit: form.unit,
    },
  };
}

/** Where this browser keeps the owner tokens of the countdowns it made: { slug: token }. */
export const OWNER_KEY = "countdowncula.owned";

/** The token an emailed edit link carries, in the URL fragment so it never reaches a server log. */
export function editLink(origin: string, slug: string, token: string): string {
  return `${origin}/c/${slug}/edit#t=${encodeURIComponent(token)}`;
}

export function tokenFromHash(hash: string): string | null {
  const match = /(?:^#|&)t=([^&]+)/.exec(hash);
  return match ? decodeURIComponent(match[1]) : null;
}

/** A plausible email address: enough to catch typos, not a validator. */
export function looksLikeEmail(s: string): boolean {
  return s.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s.trim());
}
