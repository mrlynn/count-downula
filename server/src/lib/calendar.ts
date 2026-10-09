// Calendar feeds: each shared countdown as a one-event iCalendar file at /c/<slug>/calendar.ics.
// Subscribed to (webcal:// or Google's "From URL"), the event moves when the owner edits the date,
// so an Android guest's calendar follows the wedding wherever it goes.
import type { CountdownDoc } from "./countdowns.ts";

type CalendarDoc = Pick<
  CountdownDoc,
  "slug" | "title" | "details" | "targetDate" | "updatedAt" | "createdAt" | "kind" | "timeZone" | "floating" | "pool"
>;

/** RFC 5545 text: backslashes, semicolons, commas and newlines escaped. */
export function escapeText(text: string): string {
  return text.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
}

/** Lines longer than 75 octets continue on the next line after a space. */
export function fold(line: string): string {
  const bytes = Buffer.from(line, "utf8");
  if (bytes.length <= 75) return line;
  const parts: string[] = [];
  let start = 0;
  while (start < bytes.length) {
    let end = Math.min(start + (start === 0 ? 75 : 74), bytes.length);
    // Never split a UTF-8 character: step back off continuation bytes.
    while (end < bytes.length && (bytes[end] & 0xc0) === 0x80) end--;
    parts.push(bytes.subarray(start, end).toString("utf8"));
    start = end;
  }
  return parts.join("\r\n ");
}

const pad = (n: number) => String(n).padStart(2, "0");
const utcStamp = (d: Date) =>
  `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}T${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}Z`;
const dateOnly = (y: number, m: number, d: number) => `${y}${pad(m)}${pad(d)}`;

/** The wall-clock parts of a moment in a time zone. */
function localParts(d: Date, timeZone: string) {
  let zone = timeZone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: zone, year: "numeric", month: "numeric", day: "numeric", hour: "numeric", minute: "numeric", hourCycle: "h23",
    }).formatToParts(d).map((p) => [p.type, Number(p.value)]),
  ) as Record<string, number>;
  return { year: parts.year, month: parts.month, day: parts.day, hour: parts.hour, minute: parts.minute };
}

/**
 * The date and time lines for the event: an all-day event when the countdown is to midnight in
 * the owner's zone (or a floating midnight), a floating local time for holidays, otherwise an
 * hour starting at the exact moment.
 */
export function eventTimes(doc: CalendarDoc): string[] {
  if (doc.floating) {
    const m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(doc.floating);
    if (m) {
      const [y, mo, d, h, mi] = m.slice(1).map(Number);
      if (h === 0 && mi === 0) return allDay(y, mo, d);
      return [`DTSTART:${dateOnly(y, mo, d)}T${pad(h)}${pad(mi)}00`, "DURATION:PT1H"];
    }
  }
  const local = localParts(doc.targetDate, doc.timeZone);
  if (local.hour === 0 && local.minute === 0) return allDay(local.year, local.month, local.day);
  return [`DTSTART:${utcStamp(doc.targetDate)}`, "DURATION:PT1H"];
}

function allDay(y: number, m: number, d: number): string[] {
  const next = new Date(Date.UTC(y, m - 1, d + 1));
  return [`DTSTART;VALUE=DATE:${dateOnly(y, m, d)}`, `DTEND;VALUE=DATE:${dateOnly(next.getUTCFullYear(), next.getUTCMonth() + 1, next.getUTCDate())}`];
}

/** The whole feed. Pure, for tests. */
export function icsFor(doc: CalendarDoc, url: string, now = new Date()): string {
  const countsUp = doc.kind === "countUp";
  const estimate = doc.pool && !doc.pool.answer;
  const summary = `${doc.title}${estimate ? " (estimate)" : ""}`;
  const description = [doc.details, `Count down together: ${url}`].filter(Boolean).join("\n\n");
  // Seconds since publishing: rises with every edit, so calendars know the event changed.
  const sequence = Math.max(0, Math.floor((doc.updatedAt.getTime() - doc.createdAt.getTime()) / 1000));
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Count Downcula//Live countdowns//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${escapeText(doc.title)}`,
    // Ask subscribers to check back hourly, so an owner's edit arrives the same day.
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H",
    "X-PUBLISHED-TTL:PT1H",
    "BEGIN:VEVENT",
    `UID:${doc.slug}@countdowncula.com`,
    `DTSTAMP:${utcStamp(now)}`,
    `LAST-MODIFIED:${utcStamp(doc.updatedAt)}`,
    `SEQUENCE:${sequence}`,
    ...(countsUp ? countUpTimes(doc) : eventTimes(doc)),
    `SUMMARY:${escapeText(summary)}`,
    `DESCRIPTION:${escapeText(description)}`,
    `URL:${url}`,
    "TRANSP:TRANSPARENT",
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lines.map(fold).join("\r\n") + "\r\n";
}

/** A count-up comes back every year on the day it started: anniversaries, not a single event. */
function countUpTimes(doc: CalendarDoc): string[] {
  const local = localParts(doc.targetDate, doc.timeZone);
  return [...allDay(local.year, local.month, local.day), "RRULE:FREQ=YEARLY"];
}

/** Links for the page's Add to Calendar buttons. */
export function calendarLinks(feedURL: string): { webcal: string; google: string } {
  const webcal = feedURL.replace(/^https?:\/\//, "webcal://");
  return { webcal, google: `https://calendar.google.com/calendar/r?cid=${encodeURIComponent(webcal)}` };
}
