import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { validateCryptEntry } from "../src/lib/crypt.ts";
import { HOLIDAY_RULES, LUNAR_NEW_YEAR, nthWeekday, upcomingHolidays, zodiac } from "../src/lib/holidays.ts";

const launch = JSON.parse(readFileSync(new URL("../crypt/launch.json", import.meta.url), "utf8")) as
  { slug: string; title: string; details: string; category: string; scene: string; local?: string }[];

test("the rules reproduce every hand-entered holiday and fun day", () => {
  const generated = upcomingHolidays(new Date("2026-10-09T12:00:00Z"));
  for (const entry of launch.filter((e) => e.category === "holidays" || e.category === "fun")) {
    const match = generated.find((g) => g.slug === entry.slug);
    assert.ok(match, `${entry.slug} has a rule`);
    assert.deepEqual(match, { ...entry, details: entry.details ?? "" }, entry.slug);
  }
  assert.equal(generated.length, HOLIDAY_RULES.length);
  for (const g of generated) assert.ok(validateCryptEntry(g).ok, `${g.slug} is a valid crypt entry`);
});

test("a holiday comes back for next year once it drops off", () => {
  // Halloween stays a day after its last time zone reaches midnight, then next year's takes over.
  const slugOf = (now: string, id: string) => upcomingHolidays(new Date(now)).find((e) => e.slug.startsWith(`${id}-`))?.slug;
  assert.equal(slugOf("2026-10-31T20:00:00Z", "halloween"), "halloween-2026");
  assert.equal(slugOf("2026-11-02T13:00:00Z", "halloween"), "halloween-2027");
  assert.equal(slugOf("2026-12-31T12:00:00Z", "new-year"), "new-year-2027");
  assert.equal(slugOf("2027-01-02T13:00:00Z", "new-year"), "new-year-2028");
  const ny = upcomingHolidays(new Date("2027-01-02T13:00:00Z")).find((e) => e.slug === "new-year-2028");
  assert.equal(ny?.title, "New Year 2028");
});

test("weekday rules and the lunar calendar", () => {
  assert.equal(nthWeekday(2026, 11, 4, 4), 26, "Thanksgiving 2026");
  assert.equal(nthWeekday(2027, 11, 4, 4), 25, "Thanksgiving 2027");
  assert.equal(nthWeekday(2027, 11, 0, 1), 7, "DST ends 2027");
  assert.equal(nthWeekday(2028, 11, 0, 1), 5, "DST ends 2028");
  assert.equal(zodiac(2027), "Goat");
  assert.equal(zodiac(2028), "Monkey");
  const lunar = upcomingHolidays(new Date("2027-02-08T12:00:00Z")).find((e) => e.slug.startsWith("lunar-new-year-"));
  assert.deepEqual([lunar?.slug, lunar?.local, lunar?.details], ["lunar-new-year-2028", "2028-01-26T00:00:00", "Welcome the Year of the Monkey."]);
  // Past the table, Lunar New Year is left out rather than guessed.
  const last = Math.max(...Object.keys(LUNAR_NEW_YEAR).map(Number));
  const after = upcomingHolidays(new Date(`${last}-03-01T00:00:00Z`));
  assert.ok(!after.some((e) => e.slug.startsWith("lunar-new-year-")));
});
