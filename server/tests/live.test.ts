import assert from "node:assert/strict";
import { test } from "node:test";
import { planPushes, referenceSeconds, validateRegistration, type LiveCountdown, type LiveDevice } from "../src/lib/live.ts";

const target = new Date("2026-12-31T23:59:59Z");
const countdown: LiveCountdown = {
  slug: "nye2026x", title: "New Year's Eve", kind: "event", targetDate: target,
  createdAt: new Date("2026-12-01T00:00:00Z"), style: { accent: { red: 1, green: 0.8, blue: 0.2, opacity: 1 } },
};
const phone = (id: string, extra: Partial<LiveDevice> = {}): LiveDevice => ({
  slug: "nye2026x", deviceID: id, countdownID: `${id.toUpperCase()}-0000-4000-8000-000000000000`,
  startToken: `${id}aa`.padEnd(64, "0"), activityTokens: [], sandbox: false, ...extra,
});
const at = (offsetMs: number) => new Date(target.getTime() + offsetMs);
const hour = 3_600_000;

test("dates go out the way Swift decodes them", () => {
  assert.equal(referenceSeconds(new Date("2001-01-01T00:00:00Z")), 0);
  assert.equal(referenceSeconds(new Date("2001-01-01T00:01:00Z")), 60);
});

test("each phone gets one start inside the eight hour window, with its own countdown ID", () => {
  assert.deepEqual(planPushes(countdown, [phone("a")], at(-9 * hour)), [], "Too early");
  const plan = planPushes(countdown, [phone("a"), phone("b"), phone("c", { startToken: undefined })], at(-8 * hour));
  assert.deepEqual(plan.map((p) => p.deviceID), ["a", "b"], "Phones without push-to-start are skipped");
  const aps = (plan[0].payload as { aps: Record<string, any> }).aps;
  assert.equal(aps.event, "start");
  assert.equal(aps["attributes-type"], "CountdownActivityAttributes");
  assert.equal(aps.attributes.countdownID, "A-0000-4000-8000-000000000000");
  assert.deepEqual(aps.attributes.accent, { red: 1, green: 0.8, blue: 0.2, opacity: 1 });
  assert.equal(aps["content-state"].targetDate, referenceSeconds(target));
  assert.equal(aps["content-state"].celebrating, false);
  assert.equal(aps["stale-date"], Math.floor(target.getTime() / 1000));

  const already = planPushes(countdown, [phone("a", { startedFor: target }), phone("b")], at(-2 * hour));
  assert.deepEqual(already.map((p) => p.deviceID), ["b"], "A phone that joined late still gets one; others don't get two");
  const moved = planPushes(countdown, [phone("a", { startedFor: at(-hour) })], at(-2 * hour));
  assert.equal(moved.length, 1, "A new target date starts again");
});

test("at zero, every running activity gets the celebration once", () => {
  const devices = [phone("a", { activityTokens: ["t1".padEnd(64, "0"), "t1".padEnd(64, "0")] }), phone("b", { activityTokens: ["t2".padEnd(64, "0")] })];
  const plan = planPushes(countdown, devices, at(30_000));
  assert.equal(plan.length, 2, "Duplicate tokens collapse");
  const aps = (plan[0].payload as { aps: Record<string, any> }).aps;
  assert.equal(aps.event, "end");
  assert.equal(aps["content-state"].celebrating, true);
  assert.equal(aps.alert.body, "It's here!");
  assert.deepEqual(planPushes({ ...countdown, liveEndedFor: target }, devices, at(60_000)), [], "Only once");
  assert.deepEqual(planPushes(countdown, devices, at(3 * hour)), [], "Too late to celebrate");
  assert.deepEqual(planPushes({ ...countdown, kind: "countUp" }, devices, at(-hour)), [], "Count-ups never hit zero");
});

test("registrations are checked", () => {
  const ok = validateRegistration({ deviceID: "0a0b0c0d-1111-4222-8333-444455556666",
    countdownID: "f0f0f0f0-1111-4222-8333-444455556666", startToken: "AB".repeat(40), sandbox: true });
  assert.ok(ok.ok && ok.value.countdownID === "F0F0F0F0-1111-4222-8333-444455556666" && ok.value.startToken === "ab".repeat(40));
  assert.equal(validateRegistration({ deviceID: "nope", countdownID: "f0f0f0f0-1111-4222-8333-444455556666" }).ok, false);
  assert.equal(validateRegistration({ deviceID: "0a0b0c0d-1111-4222-8333-444455556666",
    countdownID: "f0f0f0f0-1111-4222-8333-444455556666", activityToken: "xyz" }).ok, false);
});
