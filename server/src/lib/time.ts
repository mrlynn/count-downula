// Ports of the app's TimeParts and share-card headline, so the web shows the same numbers.

export type Kind = "event" | "timer" | "countUp";

export interface TimeParts {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
  isPast: boolean;
  countsUp: boolean;
}

export function timeParts(now: Date, target: Date, countsUp = false): TimeParts {
  const interval = (target.getTime() - now.getTime()) / 1000;
  let remaining = Math.floor(Math.abs(interval));
  const days = Math.floor(remaining / 86_400);
  remaining %= 86_400;
  const hours = Math.floor(remaining / 3_600);
  remaining %= 3_600;
  return {
    days,
    hours,
    minutes: Math.floor(remaining / 60),
    seconds: remaining % 60,
    isPast: !countsUp && interval <= 0,
    countsUp,
  };
}

const pad = (n: number) => String(n).padStart(2, "0");

/** "47d 3h", "3h 05m", "04:59", or "Done". */
export function compact(now: Date, target: Date, countsUp = false): string {
  const p = timeParts(now, target, countsUp);
  if (p.isPast) return "Done";
  if (p.days > 0) return `${p.days}d ${p.hours}h`;
  if (p.hours > 0) return `${p.hours}h ${pad(p.minutes)}m`;
  return `${pad(p.minutes)}:${pad(p.seconds)}`;
}

function longDate(d: Date, withYear: boolean, timeZone: string): string {
  const options: Intl.DateTimeFormatOptions = { month: "long", day: "numeric", ...(withYear ? { year: "numeric" } : {}) };
  try {
    return d.toLocaleDateString("en-US", { ...options, timeZone });
  } catch {
    return d.toLocaleDateString("en-US", { ...options, timeZone: "UTC" });
  }
}

/** The big number and the line under it, as on the app's share card. */
export function headline(
  now: Date,
  target: Date,
  kind: Kind,
  timeZone = "UTC",
): { value: string; caption: string } {
  const countsUp = kind === "countUp";
  const p = timeParts(now, target, countsUp);
  if (countsUp) {
    return p.days > 0
      ? { value: `${p.days} ${p.days === 1 ? "day" : "days"}`, caption: `since ${longDate(target, true, timeZone)}` }
      : { value: compact(now, target, true), caption: "and counting" };
  }
  if (p.isPast) return { value: "It's here!", caption: longDate(target, true, timeZone) };
  if (p.days > 0) {
    return { value: `${p.days} ${p.days === 1 ? "day" : "days"}`, caption: `to go · ${longDate(target, false, timeZone)}` };
  }
  return { value: compact(now, target), caption: "to go" };
}

/**
 * Changes whenever the preview image would show a different number. Baked into the og:image URL
 * so chat apps that cache previews by URL fetch a fresh one.
 */
export function previewKey(now: Date, target: Date, kind: Kind): string {
  const p = timeParts(now, target, kind === "countUp");
  if (p.isPast) return "done";
  if (p.days > 0) return `d${p.days}`;
  return `h${p.hours}`;
}

/** 0...1, how full the dial is: draining toward the target, filling for a count-up's day. */
export function dialRemaining(now: Date, created: Date, target: Date, kind: Kind): number {
  if (kind === "countUp") {
    const elapsedToday = ((now.getTime() - target.getTime()) / 1000) % 86_400;
    return Math.min(Math.max(elapsedToday / 86_400, 0), 1);
  }
  const total = target.getTime() - created.getTime();
  if (total <= 0 || now >= target) return 0;
  return Math.min(Math.max(1 - (now.getTime() - created.getTime()) / total, 0), 1);
}

/**
 * The real moment a countdown hits zero for this viewer. A floating time ("2027-01-01T00:00:00")
 * has no zone, so JavaScript reads it on the viewer's own clock.
 */
export function viewerTarget(countdown: { targetDate: string; floating?: string }): Date {
  return countdown.floating ? new Date(countdown.floating) : new Date(countdown.targetDate);
}
