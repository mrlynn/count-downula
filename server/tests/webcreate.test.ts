import assert from "node:assert/strict";
import { test } from "node:test";
import { webStyle } from "../src/lib/style.ts";
import { validateCountdown } from "../src/lib/validate.ts";
import { countdownPayload, editLink, lookOf, looksLikeEmail, styleFor, tokenFromHash, zonedFields, zonedTime } from "../src/lib/webCreate.ts";

test("a wall-clock time in a zone becomes the right moment, across daylight saving", () => {
  assert.equal(zonedTime("2026-12-31", "23:59", "America/New_York")?.toISOString(), "2027-01-01T04:59:00.000Z");
  assert.equal(zonedTime("2026-07-04", "21:00", "America/New_York")?.toISOString(), "2026-07-05T01:00:00.000Z");
  assert.equal(zonedTime("2026-11-01", "18:40", "Asia/Tokyo")?.toISOString(), "2026-11-01T09:40:00.000Z");
  assert.equal(zonedTime("2026-03-29", "12:00", "Europe/Berlin")?.toISOString(), "2026-03-29T10:00:00.000Z", "Just after the switch");
  assert.equal(zonedTime("2026-02-30x", "10:00", "UTC"), null);
  assert.deepEqual(zonedFields(new Date("2027-01-01T04:59:00Z"), "America/New_York"), { date: "2026-12-31", time: "23:59" });
});

test("looks become the app's style JSON, and the web draws them", () => {
  assert.deepEqual(styleFor({ scene: "fireworks" }).background, { scene: { _0: "fireworks" } });
  assert.equal(webStyle(styleFor({ scene: "fireworks" }), false).scene, "fireworks");
  assert.deepEqual(styleFor({ scene: "nonsense" }).background, { scene: { _0: "midnight" } });
  const ocean = styleFor({ gradient: "ocean" });
  assert.match(webStyle(ocean, false).background, /^linear-gradient\(180deg/);
  assert.deepEqual(lookOf(ocean), { gradient: "ocean" });
  assert.deepEqual(lookOf(styleFor({ photo: true })), { photo: true });
  assert.deepEqual(lookOf(styleFor({ scene: "baby" })), { scene: "baby" });
});

test("the form becomes a publish payload the server accepts", () => {
  const now = new Date("2026-10-09T12:00:00Z");
  const form = { title: "  Maya turns 7 ", details: "Park, 3pm", date: "2026-10-24", time: "15:00", timeZone: "America/Chicago", look: { scene: "birthday" }, unit: "sleeps" as const };
  const built = countdownPayload(form, now);
  assert.ok(built.ok);
  if (!built.ok) return;
  assert.equal(built.countdown.title, "Maya turns 7");
  assert.equal(built.countdown.targetDate, "2026-10-24T20:00:00.000Z");
  const valid = validateCountdown(built.countdown);
  assert.ok(valid.ok && valid.value.unit === "sleeps" && valid.value.timeZone === "America/Chicago");
  assert.deepEqual(countdownPayload({ ...form, title: " " }, now), { ok: false, error: "title" });
  assert.deepEqual(countdownPayload({ ...form, date: "2026-10-01" }, now), { ok: false, error: "past" });
  assert.deepEqual(countdownPayload({ ...form, date: "" }, now), { ok: false, error: "date" });
});

test("edit links carry the token in the fragment", () => {
  const link = editLink("https://go.countdowncula.com", "abcd2345", "tok/en+=");
  assert.equal(link, "https://go.countdowncula.com/c/abcd2345/edit#t=tok%2Fen%2B%3D");
  assert.equal(tokenFromHash(new URL(link).hash), "tok/en+=");
  assert.equal(tokenFromHash(""), null);
  assert.ok(looksLikeEmail("sam@example.com"));
  assert.ok(!looksLikeEmail("sam@example"));
});

test("replies go to EMAIL_REPLY_TO when it's set", async () => {
  const { replyTo } = await import("../src/lib/email.ts");
  assert.deepEqual(replyTo({ EMAIL_REPLY_TO: "countdowncula@gmail.com" }), { reply_to: "countdowncula@gmail.com" });
  assert.deepEqual(replyTo({}), {});
});
