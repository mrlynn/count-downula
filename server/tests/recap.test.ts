import assert from "node:assert/strict";
import { test } from "node:test";
import { keptCountingAfter } from "../src/lib/countdowns.ts";
import { countedSpan, isFinished, recapText } from "../src/lib/recapText.ts";

const now = new Date("2026-10-31T12:00:00Z");
const zero = new Date("2026-10-31T00:00:00Z");

test("a recap reads like the spec: days, people, notes, the winner", () => {
  const words = recapText({ counted: { days: 142, hours: 3_408 }, people: 23, notes: 41, closest: ["Dana"] });
  assert.equal(words.counted, "142 days counted");
  assert.equal(words.people, "23 of us · 41 notes in the coffin · Dana guessed closest");
  assert.equal(words.together, "23 counted down together");
});

test("a solo countdown has no people line, and short waits count hours", () => {
  const words = recapText({ counted: { days: 0, hours: 5 }, people: 1, notes: 0, closest: [] });
  assert.deepEqual(words, { counted: "5 hours counted", people: null, together: null });
  assert.equal(recapText({ counted: { days: 1, hours: 30 }, people: 1, notes: 1, closest: [] }).counted, "1 day counted");
  assert.equal(recapText({ counted: { days: 0, hours: 0 }, people: 1, notes: 0, closest: [] }).counted, null);
});

test("public entries speak of everyone, and ties name each winner", () => {
  const words = recapText({ people: 1204, notes: 0, closest: ["Ana", "Ben", "Cy"] }, true);
  assert.equal(words.counted, null);
  assert.equal(words.people, "1,204 counted down · Ana, Ben and Cy guessed closest");
});

test("counted spans run from creation to zero", () => {
  assert.deepEqual(countedSpan(new Date("2026-06-11T00:00:00Z"), zero), { days: 142, hours: 3_408 });
  assert.deepEqual(countedSpan(zero, new Date("2026-06-11T00:00:00Z")), { days: 0, hours: 0 }, "Never negative");
});

test("finished means past zero, or kept counting up from it", () => {
  assert.ok(isFinished({ kind: "event", targetDate: zero }, now));
  assert.ok(!isFinished({ kind: "event", targetDate: new Date("2026-11-01T00:00:00Z") }, now));
  assert.ok(!isFinished({ kind: "countUp", targetDate: zero }, now), "A count-up from the start never finished");
  assert.ok(isFinished({ kind: "countUp", targetDate: zero, keptCounting: true }, now));
});

test("keeping a finished countdown counting is noticed, and so is turning it back", () => {
  const finished = { kind: "event" as const, targetDate: zero };
  assert.equal(keptCountingAfter(finished, { kind: "countUp", targetDate: zero }, now), true);
  assert.equal(keptCountingAfter(finished, { kind: "countUp", targetDate: new Date("2026-01-01") }, now), undefined,
    "A different start is just an edit");
  assert.equal(keptCountingAfter({ kind: "event", targetDate: new Date("2026-11-05") }, { kind: "countUp", targetDate: new Date("2026-11-05") }, now),
    undefined, "Not before zero");
  const kept = { kind: "countUp" as const, targetDate: zero, keptCounting: true };
  assert.equal(keptCountingAfter(kept, { kind: "countUp", targetDate: zero }, now), undefined);
  assert.equal(keptCountingAfter(kept, { kind: "event", targetDate: zero }, now), false);
});
