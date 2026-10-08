import assert from "node:assert/strict";
import { test } from "node:test";
import { gradientCss, webStyle } from "../src/lib/style.ts";
import { compact, dialRemaining, headline, previewKey, timeParts } from "../src/lib/time.ts";
import { isSlug, makeSlug, validateCountdown, validatePhoto } from "../src/lib/validate.ts";

const now = new Date("2026-10-08T12:00:00Z");

test("timeParts splits the interval like the app", () => {
  const p = timeParts(now, new Date("2026-10-31T15:30:45Z"));
  assert.deepEqual([p.days, p.hours, p.minutes, p.seconds, p.isPast], [23, 3, 30, 45, false]);
  assert.equal(timeParts(now, new Date("2026-10-01T00:00:00Z")).isPast, true);
  assert.equal(timeParts(now, new Date("2026-10-01T00:00:00Z"), true).isPast, false);
});

test("compact matches the menu bar format", () => {
  assert.equal(compact(now, new Date("2026-10-10T16:00:00Z")), "2d 4h");
  assert.equal(compact(now, new Date("2026-10-08T15:05:00Z")), "3h 05m");
  assert.equal(compact(now, new Date("2026-10-08T12:04:59Z")), "04:59");
  assert.equal(compact(now, new Date("2026-10-08T11:00:00Z")), "Done");
});

test("headline reads like the share card and respects the owner's time zone", () => {
  // 9pm on Halloween in New York is already November 1 in UTC.
  const target = new Date("2026-11-01T01:00:00Z");
  assert.deepEqual(headline(now, target, "event", "America/New_York"), { value: "23 days", caption: "to go · October 31" });
  assert.deepEqual(headline(now, target, "event", "Not/AZone"), { value: "23 days", caption: "to go · November 1" });
  assert.equal(headline(now, new Date("2026-10-01T00:00:00Z"), "event").value, "It's here!");
  assert.deepEqual(headline(now, new Date("2026-10-07T12:00:00Z"), "countUp", "UTC"), { value: "1 day", caption: "since October 7, 2026" });
});

test("previewKey changes with the day, and with the hour on the last day", () => {
  assert.equal(previewKey(now, new Date("2026-10-31T12:00:00Z"), "event"), "d23");
  assert.equal(previewKey(now, new Date("2026-10-08T17:00:00Z"), "event"), "h5");
  assert.equal(previewKey(now, new Date("2026-10-01T00:00:00Z"), "event"), "done");
});

test("dialRemaining drains toward the target", () => {
  const created = new Date("2026-10-06T12:00:00Z");
  assert.equal(dialRemaining(now, created, new Date("2026-10-10T12:00:00Z"), "event"), 0.5);
  assert.equal(dialRemaining(now, created, new Date("2026-10-07T12:00:00Z"), "event"), 0);
});

test("webStyle decodes Swift's enum encoding", () => {
  const gradient = webStyle({ background: { gradient: { _0: { stops: [{ red: 1, green: 0, blue: 0 }, { red: 0, green: 0, blue: 1 }], angle: 0 } } } }, true);
  assert.equal(gradient.background, "linear-gradient(90deg, rgba(255, 0, 0, 1), rgba(0, 0, 255, 1))");
  assert.equal(gradient.useImage, false);

  const solid = webStyle({ background: { solid: { _0: { red: 0, green: 0.5, blue: 0, opacity: 1 } } }, textColor: { red: 0, green: 0, blue: 0 } }, false);
  assert.equal(solid.background, "rgba(0, 128, 0, 1)");
  assert.equal(solid.lightText, false);

  const scene = webStyle({ background: { scene: { _0: "harvestMoon" } }, font: "serif", weight: "black" }, true);
  assert.equal(scene.useImage, true);
  assert.match(scene.fontFamily, /Young Serif/);
  assert.equal(scene.fontWeight, 900);

  const fallback = webStyle(null, false);
  assert.equal(fallback.useImage, false);
  assert.equal(fallback.accent, "rgba(217, 23, 51, 1)");
  assert.equal(gradientCss({ stops: [] }), fallback.background);
});

test("validateCountdown accepts the app's payload and rejects bad input", () => {
  const ok = validateCountdown({ title: "  Sonoma  ", details: "", targetDate: "2026-10-31T19:00:00Z", kind: "event", timeZone: "America/New_York", style: {}, milestones: [] });
  assert.ok(ok.ok);
  if (ok.ok) {
    assert.equal(ok.value.title, "Sonoma");
    assert.equal(ok.value.timeZone, "America/New_York");
  }
  assert.equal(validateCountdown({ title: "", targetDate: "2026-10-31" }).ok, false);
  assert.equal(validateCountdown({ title: "x", targetDate: "nope" }).ok, false);
  assert.equal(validateCountdown({ title: "x".repeat(121), targetDate: "2026-10-31" }).ok, false);
  const odd = validateCountdown({ title: "x", targetDate: "2026-10-31", kind: "weird", timeZone: "Mars/Base" });
  assert.ok(odd.ok && odd.value.kind === "event" && odd.value.timeZone === "UTC");
});

test("validatePhoto only takes small JPEGs", () => {
  assert.equal(validatePhoto(undefined).ok, true);
  assert.deepEqual(validatePhoto(null), { ok: true, value: null });
  const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]).toString("base64");
  assert.equal(validatePhoto(jpeg).ok, true);
  assert.equal(validatePhoto(Buffer.from("GIF89a").toString("base64")).ok, false);
  assert.equal(validatePhoto(Buffer.alloc(401 * 1024, 0xff).toString("base64")).ok, false);
});

test("slugs avoid look-alike characters", () => {
  const slug = makeSlug((n) => new Uint8Array(n).map((_, i) => i * 31));
  assert.equal(slug.length, 8);
  assert.doesNotMatch(slug, /[01lIoO]/);
  assert.ok(isSlug(slug));
  assert.ok(!isSlug("../etc"));
});
