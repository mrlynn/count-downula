import assert from "node:assert/strict";
import { test } from "node:test";
import { countdownJsonLd, eventDateText, jsonLdHTML, titleWithYear } from "../src/lib/seo.ts";
import type { PublicCountdown } from "../src/lib/countdowns.ts";

const halloween = { targetDate: "2026-10-31T00:00:00.000Z", floating: "2026-10-31T00:00:00" };
const eclipse = { targetDate: "2027-08-02T10:07:00.000Z" };

test("titles get the year unless they already say one", () => {
  assert.equal(titleWithYear("Halloween", halloween), "Halloween 2026");
  assert.equal(titleWithYear("World Cup Final 2026", halloween), "World Cup Final 2026");
});

test("floating dates are the same day everywhere; exact moments say UTC", () => {
  assert.equal(eventDateText(halloween, "en"), "Saturday, October 31, 2026");
  assert.equal(eventDateText(halloween, "de"), "Samstag, 31. Oktober 2026");
  assert.match(eventDateText(eclipse, "en"), /^Monday, August 2, 2027 at 10:07\sAM UTC$/);
});

test("the structured data describes the event, dated by day when floating", () => {
  const c = { ...halloween, title: "Halloween", details: "The Count's favorite night." } as PublicCountdown;
  const ld = countdownJsonLd(c, "https://go.example/c/halloween-2026", "https://go.example/c/halloween-2026/og");
  assert.equal(ld.about.name, "Halloween 2026");
  assert.equal(ld.about.startDate, "2026-10-31");
  assert.equal(ld.about.description, "The Count's favorite night.");
  const exact = countdownJsonLd({ ...eclipse, title: "Total eclipse", details: "" } as PublicCountdown, "u", "i");
  assert.equal(exact.about.startDate, eclipse.targetDate);
  assert.equal("description" in exact.about, false);
});

test("a title can't close the script tag", () => {
  assert.equal(jsonLdHTML({ name: "</script><b>" }).includes("</script>"), false);
});
