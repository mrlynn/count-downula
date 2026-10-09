import assert from "node:assert/strict";
import { test } from "node:test";
import { calendarLinks, escapeText, eventTimes, fold, icsFor } from "../src/lib/calendar.ts";
import { calendarApp } from "../src/lib/calendarClients.ts";
import { coffinRefusal } from "../src/lib/coffin.ts";
import { embeddable, embedOptions, embedSnippet } from "../src/lib/embed.ts";

const base = {
  slug: "k7Pq2mXa", title: "Maya & Theo's Wedding", details: "Sonoma, 4pm; dress up, please",
  targetDate: new Date("2026-11-21T23:00:00Z"), createdAt: new Date("2026-06-01T00:00:00Z"),
  updatedAt: new Date("2026-06-01T00:10:00Z"), kind: "event" as const, timeZone: "America/Los_Angeles",
};
const now = new Date("2026-10-09T12:00:00Z");

test("a timed countdown is an hour from its exact moment", () => {
  assert.deepEqual(eventTimes(base), ["DTSTART:20261121T230000Z", "DURATION:PT1H"]);
});

test("midnight in the owner's zone is an all-day event on that day", () => {
  const midnight = { ...base, targetDate: new Date("2026-11-21T08:00:00Z") };  // 00:00 in Los Angeles
  assert.deepEqual(eventTimes(midnight), ["DTSTART;VALUE=DATE:20261121", "DTEND;VALUE=DATE:20261122"]);
});

test("floating holidays stay floating, and floating midnight is all day", () => {
  const nye = { ...base, timeZone: "UTC", floating: "2027-01-01T00:00:00" };
  assert.deepEqual(eventTimes(nye), ["DTSTART;VALUE=DATE:20270101", "DTEND;VALUE=DATE:20270102"]);
  const fireworks = { ...base, timeZone: "UTC", floating: "2026-07-04T21:30:00" };
  assert.deepEqual(eventTimes(fireworks), ["DTSTART:20260704T213000", "DURATION:PT1H"]);
});

test("the feed is valid iCalendar with escaped, folded text", () => {
  const ics = icsFor(base, "https://go.countdowncula.com/c/k7Pq2mXa", now);
  assert.ok(ics.startsWith("BEGIN:VCALENDAR\r\nVERSION:2.0\r\n"));
  assert.ok(ics.endsWith("END:VCALENDAR\r\n"));
  assert.match(ics, /UID:k7Pq2mXa@countdowncula\.com/);
  assert.match(ics, /SUMMARY:Maya & Theo's Wedding/);
  assert.match(ics, /SEQUENCE:600/, "Rises with each edit");
  assert.match(ics, /DESCRIPTION:Sonoma\\, 4pm\\; dress up\\, please\\n\\nCount down/);
  for (const line of ics.split("\r\n")) assert.ok(Buffer.byteLength(line) <= 75, `Line too long: ${line}`);
});

test("estimates say so, and count-ups come back every year", () => {
  assert.match(icsFor({ ...base, pool: { closed: false } }, "u", now), /SUMMARY:Maya & Theo's Wedding \(estimate\)/);
  const sober = icsFor({ ...base, kind: "countUp", targetDate: new Date("2025-03-02T18:00:00Z") }, "u", now);
  assert.match(sober, /DTSTART;VALUE=DATE:20250302/);
  assert.match(sober, /RRULE:FREQ=YEARLY/);
});

test("text escaping and folding follow RFC 5545", () => {
  assert.equal(escapeText("a\\b;c,d\ne"), "a\\\\b\\;c\\,d\\ne");
  const folded = fold("DESCRIPTION:" + "🦇".repeat(30));
  assert.ok(folded.split("\r\n ").every((part) => Buffer.byteLength(part) <= 75));
  assert.equal(folded.split("\r\n ").join(""), "DESCRIPTION:" + "🦇".repeat(30), "No character split");
});

test("subscribe links", () => {
  const links = calendarLinks("https://go.countdowncula.com/c/k7Pq2mXa/calendar.ics");
  assert.equal(links.webcal, "webcal://go.countdowncula.com/c/k7Pq2mXa/calendar.ics");
  assert.equal(links.google, "https://calendar.google.com/calendar/r?cid=webcal%3A%2F%2Fgo.countdowncula.com%2Fc%2Fk7Pq2mXa%2Fcalendar.ics");
});

test("calendar apps are told apart by user agent", () => {
  assert.equal(calendarApp("Google-Calendar-Importer"), "google");
  assert.equal(calendarApp("iOS/26.0 (23A341) dataaccessd/1.0"), "apple");
  assert.equal(calendarApp("Microsoft Office/16.0"), "outlook");
  assert.equal(calendarApp("Mozilla/5.0 (Android)"), "browser");
});

test("the coffin takes drops only while a shared countdown is counting", () => {
  assert.equal(coffinRefusal({ ...base, visibility: "link" }, now), null);
  assert.match(coffinRefusal({ ...base, visibility: "public" }, now)!, /Public/);
  assert.match(coffinRefusal({ ...base, kind: "countUp", visibility: "link" }, now)!, /Count-ups/);
  assert.match(coffinRefusal({ ...base, visibility: "link", targetDate: new Date("2026-10-01") }, now)!, /already open/);
});

test("embed options fall back to safe defaults", () => {
  assert.deepEqual(embedOptions({}), { theme: "style", end: "message", message: "It's here!" });
  assert.deepEqual(embedOptions({ theme: "light", end: "recap", message: "  Doors open!\n" }), { theme: "light", end: "recap", message: "Doors open!" });
  assert.equal(embedOptions({ theme: "neon", end: "redirect" }).end, "message", "No redirects: that waits for the host tier");
  assert.equal(embedOptions({ message: "x".repeat(200) }).message.length, 80);
});

test("private count-ups can't be embedded; kept-counting ones can", () => {
  assert.ok(embeddable({ kind: "event" }));
  assert.ok(!embeddable({ kind: "countUp" }));
  assert.ok(embeddable({ kind: "countUp", keptCounting: true }));
  assert.equal(embedSnippet("https://go.countdowncula.com", "k7Pq2mXa"),
    '<script async src="https://go.countdowncula.com/embed.js" data-countdown="k7Pq2mXa"></script>');
});
