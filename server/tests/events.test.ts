import assert from "node:assert/strict";
import { test } from "node:test";
import { metricsAuthorized } from "../src/lib/adminAuth.ts";
import { BATCH_LIMIT, clientOf, referrerSource, validateBatch } from "../src/lib/events.ts";
import { buildCohorts, startOfWeek } from "../src/lib/metrics.ts";

const now = new Date("2026-10-09T12:00:00Z");
const batch = (events: unknown[], extra: Record<string, unknown> = {}) => ({
  installId: "3F2504E0-4F89-11D3-9A0C-0305E82C3301", platform: "ios", appVersion: "1.2.0", events, ...extra,
});
const req = (headers: Record<string, string>) => new Request("https://go.countdowncula.com/", { headers });

test("the app header names the platform and version", () => {
  assert.deepEqual(clientOf(req({ "x-countdowncula-client": "ios/1.2.0" })), { platform: "ios", appVersion: "1.2.0" });
  assert.deepEqual(clientOf(req({ "x-countdowncula-client": "clip/1.2.0" })), { platform: "clip", appVersion: "1.2.0" });
  assert.deepEqual(clientOf(req({ "x-countdowncula-client": "macos/not a version" })), { platform: "unknown" });
});

test("without the header, browsers are the web and the rest is unknown", () => {
  assert.deepEqual(clientOf(req({ "user-agent": "Mozilla/5.0 (Linux; Android 15)" })), { platform: "web" });
  assert.deepEqual(clientOf(req({ "user-agent": "Countdownula/12 CFNetwork/3826 Darwin/25.0.0" })), { platform: "unknown" });
  assert.deepEqual(clientOf(req({ "x-countdowncula-client": "web/1.0", "user-agent": "curl/8" })), { platform: "unknown" },
    "The app header can't claim to be the web");
});

test("referrers keep only the host, and our own pages don't count", () => {
  assert.equal(referrerSource("https://www.Google.com/search?q=secret", "go.countdowncula.com"), "google.com");
  assert.equal(referrerSource("https://go.countdowncula.com/crypt", "go.countdowncula.com"), undefined);
  assert.equal(referrerSource("not a url", "go.countdowncula.com"), undefined);
  assert.equal(referrerSource(null, "go.countdowncula.com"), undefined);
});

test("a good batch becomes one document per event, tagged with the install", () => {
  const result = validateBatch(batch([
    { name: "countdown_created", at: "2026-10-09T11:00:00Z", source: "screenshot" },
    { name: "install_from_link", at: "2026-10-09T11:59:00Z", slug: "k7Pq2mXa" },
  ]), now);
  assert.ok(result.ok);
  assert.equal(result.docs.length, 2);
  assert.deepEqual(result.docs[0], {
    name: "countdown_created", platform: "ios", appVersion: "1.2.0", installId: "3F2504E0-4F89-11D3-9A0C-0305E82C3301",
    at: new Date("2026-10-09T11:00:00Z"), source: "screenshot",
  });
  assert.equal(result.docs[1].slug, "k7Pq2mXa");
});

test("unknown, stale, future and malformed events are dropped, not refused", () => {
  const result = validateBatch(batch([
    { name: "something_from_a_newer_app", at: "2026-10-09T11:00:00Z" },
    { name: "publish", at: "2026-10-09T11:00:00Z" },
    { name: "active", at: "2026-08-01T00:00:00Z" },
    { name: "active", at: "2026-10-10T00:00:00Z" },
    { name: "active", at: "yesterday" },
    { name: "active", at: "2026-10-09T12:05:00Z", slug: "../../etc", source: "Has Spaces" },
    "nonsense",
  ]), now);
  assert.ok(result.ok);
  assert.equal(result.dropped, 6, "Only the slightly-ahead clock survives; server events can't be sent by the app");
  assert.deepEqual(result.docs[0].at, now, "A clock a few minutes fast is pulled back to now");
  assert.equal(result.docs[0].slug, undefined);
  assert.equal(result.docs[0].source, undefined);
});

test("the batch envelope must be right", () => {
  assert.equal(validateBatch(null).ok, false);
  assert.equal(validateBatch(batch([], { installId: "short" })).ok, false);
  assert.equal(validateBatch(batch([], { platform: "web" })).ok, false, "The web doesn't send batches");
  assert.equal(validateBatch(batch([], { appVersion: "" })).ok, false);
  assert.equal(validateBatch(batch(Array(BATCH_LIMIT + 1).fill({ name: "active", at: now.toISOString() }))).ok, false);
});

test("weeks start on Monday in UTC", () => {
  assert.equal(startOfWeek(new Date("2026-10-09T23:00:00Z")).toISOString(), "2026-10-05T00:00:00.000Z");
  assert.equal(startOfWeek(new Date("2026-10-05T00:00:00Z")).toISOString(), "2026-10-05T00:00:00.000Z");
  assert.equal(startOfWeek(new Date("2026-10-11T23:59:59Z")).toISOString(), "2026-10-05T00:00:00.000Z");
});

test("cohorts count each install once, by its first week, and leave future weeks blank", () => {
  const w = (iso: string) => new Date(`${iso}T00:00:00Z`);
  const rows = [
    { first: w("2026-09-28"), activeWeeks: [w("2026-09-28"), w("2026-10-05")] },
    { first: w("2026-09-28"), activeWeeks: [w("2026-09-28")] },
    { first: w("2026-10-05"), activeWeeks: [w("2026-10-05")] },
  ];
  const [thisWeek, lastWeek] = buildCohorts(rows, 3, new Date("2026-10-09T12:00:00Z"));
  assert.deepEqual(thisWeek, { week: "2026-10-05", size: 1, retained: [1, null, null] });
  assert.deepEqual(lastWeek, { week: "2026-09-28", size: 2, retained: [1, 0.5, null] });
});

test("the dashboard needs the password, and a long one", () => {
  const basic = (s: string) => `Basic ${Buffer.from(s).toString("base64")}`;
  const password = "correct horse battery";
  assert.ok(metricsAuthorized(basic(`anyone:${password}`), password));
  assert.ok(metricsAuthorized(basic(`me:with:colons:${password}`), "with:colons:" + password));
  assert.ok(!metricsAuthorized(basic("anyone:wrong"), password));
  assert.ok(!metricsAuthorized(null, password));
  assert.ok(!metricsAuthorized(basic("anyone:short"), "short"), "Too short to be safe, so never open");
});
