import assert from "node:assert/strict";
import { test } from "node:test";
import { headline, previewKey } from "../src/lib/time.ts";
import { reading, sleeps, unitFits, weekends, workdays } from "../src/lib/units.ts";
import { validateCountdown } from "../src/lib/validate.ts";

const NY = "America/New_York";
// Clock times in New York (October is UTC-4, December UTC-5).
const oct = (d: number, h = 0) => new Date(Date.UTC(2026, 9, d, h + 4));
const dec = (d: number, h = 0) => new Date(Date.UTC(2026, 11, d, h + 5));

test("sleeps match the app: Christmas Eve morning is one", () => {
  assert.equal(sleeps(dec(24, 10), dec(25), 0, NY), 1);
  assert.equal(sleeps(dec(24, 10), dec(25, 7), 0, NY), 1);
  assert.equal(sleeps(dec(20, 10), dec(25), 0, NY), 5);
  assert.equal(sleeps(dec(24, 19), dec(25, 7), 20 * 60, NY), 1);
  assert.equal(sleeps(dec(24, 21), dec(25, 7), 20 * 60, NY), 0, "Already in bed");
});

test("workdays count today and skip weekends; weekends include the one under way", () => {
  // Friday, October 9, 2026.
  assert.equal(workdays(oct(9, 9), oct(19), NY), 6);
  assert.equal(workdays(oct(9, 9), oct(12, 9), NY), 1);
  assert.equal(workdays(oct(9, 9), oct(9, 17), NY), 0);
  assert.equal(workdays(oct(9, 9), new Date(Date.UTC(2027, 9, 8, 4)), NY), 260);
  assert.equal(weekends(oct(9, 9), oct(19), NY), 2);
  assert.equal(weekends(oct(10, 9), oct(12), NY), 1);
  assert.equal(weekends(oct(11, 9), oct(19), NY), 2);
  assert.equal(weekends(oct(12, 9), oct(16), NY), 0);
});

test("a reading follows the app's rules", () => {
  const now = oct(9, 9);
  const event = (unit: "weeks" | "sleeps" | "percent", target: Date, kind: "event" | "countUp" | "timer" = "event") =>
    reading({ kind, unit, createdAt: new Date(now.getTime() - 99_999_000) }, now, target, "en", NY);

  assert.deepEqual(event("weeks", new Date(now.getTime() + (47 * 86_400 + 3_600) * 1000))?.text, "6 weeks, 5 days");
  assert.equal(event("weeks", new Date(now.getTime() + 6 * 86_400_000)), null, "The last week ticks");
  assert.equal(event("sleeps", oct(12, 9))?.text, "3 sleeps");
  assert.equal(event("sleeps", oct(12, 9), "countUp"), null, "Sleeps don't fit a count-up");
  assert.equal(event("percent", new Date(now.getTime() + 1000))?.text, "99%");
  assert.equal(event("sleeps", new Date(now.getTime() - 1000)), null, "Done");
  assert.equal(reading({ kind: "event", createdAt: now }, now, oct(20), "en", NY), null, "No unit");
  assert.equal(unitFits("percent", "timer"), true);
  assert.equal(unitFits("weeks", "timer"), false);
});

test("units read in the viewer's language", () => {
  const now = oct(9, 9);
  const r = reading({ kind: "event", unit: "sleeps", createdAt: now }, now, oct(12, 9), "fr", NY);
  assert.equal(r?.text, "3 dodos");
  assert.equal(reading({ kind: "event", unit: "workdays", createdAt: now }, now, oct(12, 9), "de", NY)?.text, "1 Arbeitstag");
});

test("previews say the unit and change when it does", () => {
  const now = oct(9, 9);
  const r = reading({ kind: "event", unit: "sleeps", createdAt: now }, now, oct(12, 9), "en", NY);
  assert.deepEqual(headline(now, oct(12, 9), "event", NY, "en", r), { value: "3 sleeps", caption: "to go · October 12" });
  assert.equal(previewKey(now, oct(12, 9), "event", r), "u3%20sleeps");
  const p = reading({ kind: "event", unit: "percent", createdAt: oct(1) }, now, oct(17), "en", NY);
  assert.equal(headline(now, oct(17), "event", NY, "en", p).caption, "of the way there · October 17");
});

test("publish takes a unit, ignores one it doesn't know, and only keeps a bedtime for sleeps", () => {
  const base = { title: "Christmas", targetDate: "2026-12-25T05:00:00Z" };
  const sleepy = validateCountdown({ ...base, unit: "sleeps", bedtime: 1_200 });
  assert.ok(sleepy.ok && sleepy.value.unit === "sleeps" && sleepy.value.bedtime === 1_200);
  const weeks = validateCountdown({ ...base, unit: "weeks", bedtime: 1_200 });
  assert.ok(weeks.ok && weeks.value.bedtime === null);
  const future = validateCountdown({ ...base, unit: "fortnights" });
  assert.ok(future.ok && future.value.unit === "daysHours");
  const old = validateCountdown(base);
  assert.ok(old.ok && !("unit" in old.value), "Older apps leave the unit alone");
  const bad = validateCountdown({ ...base, unit: "sleeps", bedtime: 5_000 });
  assert.ok(bad.ok && bad.value.bedtime === null);
});
