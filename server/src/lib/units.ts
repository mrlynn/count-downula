// What a countdown counts in, ported from the app's CountUnits.swift so the live page, embeds and
// previews read "12 sleeps" too. Days are counted on the viewer's calendar in the browser, and in
// the countdown's own zone on the server. Weekends are Saturday and Sunday here; the app follows
// the region's calendar.
import { t, type Locale } from "./i18n.ts";
import { timeParts, type Kind } from "./time.ts";

export const UNITS = ["daysHours", "weeks", "sleeps", "workdays", "weekends", "percent"] as const;
export type Unit = (typeof UNITS)[number];

export function isUnit(v: unknown): v is Unit {
  return (UNITS as readonly unknown[]).includes(v);
}

/** Same rule as the app: sleeps, workdays and weekends need a date ahead; percent needs an end. */
export function unitFits(unit: Unit, kind: Kind): boolean {
  switch (unit) {
    case "daysHours": return true;
    case "weeks": return kind !== "timer";
    case "sleeps": case "workdays": case "weekends": return kind === "event";
    case "percent": return kind !== "countUp";
  }
}

/** A calendar day number (days since 1970-01-01) and minutes after midnight, in a zone or locally. */
export function dayClock(d: Date, timeZone?: string): { day: number; minutes: number } {
  if (!timeZone) {
    return {
      day: Math.round(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()) / 86_400_000),
      minutes: d.getHours() * 60 + d.getMinutes(),
    };
  }
  let zone = timeZone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: zone, year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric", hourCycle: "h23",
    }).formatToParts(d).map((p) => [p.type, p.value]),
  );
  return {
    day: Math.round(Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day)) / 86_400_000),
    minutes: Number(parts.hour) * 60 + Number(parts.minute),
  };
}

/** 0 is Sunday. Day 0 (January 1, 1970) was a Thursday. */
const weekday = (day: number) => (((day + 4) % 7) + 7) % 7;
const isWeekend = (day: number) => weekday(day) === 0 || weekday(day) === 6;

/** Days in [first, first + n) that pass a test that repeats weekly, without walking years of days. */
function countDays(first: number, n: number, test: (day: number) => boolean): number {
  if (n <= 0) return 0;
  let perWeek = 0;
  for (let i = 0; i < 7; i++) if (test(first + i)) perWeek++;
  let tail = 0;
  for (let i = Math.floor(n / 7) * 7; i < n; i++) if (test(first + i)) tail++;
  return Math.floor(n / 7) * perWeek + tail;
}

/** A sleep at each bedtime (minutes after midnight) after now and no later than the target. */
export function sleeps(now: Date, target: Date, bedtime = 0, timeZone?: string): number {
  if (target <= now) return 0;
  const a = dayClock(now, timeZone), b = dayClock(target, timeZone);
  let count = b.day - a.day + 1;
  if (a.minutes >= bedtime) count--;
  if (b.minutes < bedtime) count--;
  return Math.max(0, count);
}

/** Weekdays from today up to the day before the target. */
export function workdays(now: Date, target: Date, timeZone?: string): number {
  if (target <= now) return 0;
  const a = dayClock(now, timeZone).day, b = dayClock(target, timeZone).day;
  return countDays(a, b - a, (d) => !isWeekend(d));
}

/** Weekends before the target day, this one included if it's under way. */
export function weekends(now: Date, target: Date, timeZone?: string): number {
  if (target <= now) return 0;
  const a = dayClock(now, timeZone).day, b = dayClock(target, timeZone).day;
  const starts = countDays(a, b - a, (d) => isWeekend(d) && !isWeekend(d - 1));
  return starts + (b > a && isWeekend(a) && isWeekend(a - 1) ? 1 : 0);
}

export interface Reading {
  /** "12 sleeps", "6 weeks, 5 days", "82%". */
  text: string;
  /** The big readout, in place of days, hours, minutes and seconds. */
  tiles: { value: string; label: string }[];
  /** Percent reads "82% of the way there", not "82% to go". */
  isPercent: boolean;
}

/**
 * The countdown in its unit, or null for days and hours: when that's the unit, once it's done, and
 * in the final stretch where the ticking clock says more. Same rules as the app.
 */
export function reading(
  countdown: { kind: Kind; unit?: Unit; bedtime?: number; createdAt: string | Date },
  now: Date,
  target: Date,
  locale: Locale,
  timeZone?: string,
): Reading | null {
  const unit = countdown.unit;
  if (!unit || unit === "daysHours" || !unitFits(unit, countdown.kind)) return null;
  const countsUp = countdown.kind === "countUp";
  const p = timeParts(now, target, countsUp);
  if (p.isPast) return null;
  const single = (n: number, key: "nSleeps" | "nWorkdays" | "nWeekends", label: "uSleeps" | "uWorkdays" | "uWeekends") =>
    n > 0 ? { text: t(locale, key, { n }), tiles: [{ value: String(n), label: t(locale, label) }], isPercent: false } : null;
  switch (unit) {
    case "weeks": {
      if (p.days < 7) return null;
      const w = Math.floor(p.days / 7), d = p.days % 7;
      const weeks = t(locale, "nWeeks", { n: w });
      return {
        text: d > 0 ? t(locale, "weeksDays", { weeks, days: t(locale, "nDays", { n: d }) }) : weeks,
        tiles: [{ value: String(w), label: t(locale, "uWeeks") }, { value: String(d), label: t(locale, "days") }],
        isPercent: false,
      };
    }
    case "sleeps": return single(sleeps(now, target, countdown.bedtime ?? 0, timeZone), "nSleeps", "uSleeps");
    case "workdays": return single(workdays(now, target, timeZone), "nWorkdays", "uWorkdays");
    case "weekends": return single(weekends(now, target, timeZone), "nWeekends", "uWeekends");
    case "percent": {
      const created = new Date(countdown.createdAt).getTime();
      const total = target.getTime() - created;
      const fraction = total > 0 ? Math.min(Math.max((now.getTime() - created) / total, 0), 1) : 1;
      // Rounded down, so it never reads 100% before zero.
      const value = new Intl.NumberFormat(locale, { style: "percent", maximumFractionDigits: 0 })
        .format(Math.floor(fraction * 100) / 100);
      return { text: value, tiles: [{ value, label: t(locale, "uThere") }], isPercent: true };
    }
    default: return null;
  }
}
