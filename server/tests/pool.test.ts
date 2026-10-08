import assert from "node:assert/strict";
import { test } from "node:test";
import { ObjectId } from "mongodb";
import { rankGuesses, validateGuess, validatePoolAction, type GuessDoc } from "../src/lib/pool.ts";
import { poolFlag } from "../src/lib/validate.ts";

const now = new Date("2026-10-08T12:00:00Z");

test("a guess needs a name and a date that hasn't passed or isn't absurdly far", () => {
  assert.ok(validateGuess({ name: "Priya", guess: "2026-12-01T09:00:00Z" }, now).ok);
  assert.equal(validateGuess({ name: " ", guess: "2026-12-01T09:00:00Z" }, now).ok, false);
  assert.equal(validateGuess({ name: "x".repeat(41), guess: "2026-12-01T09:00:00Z" }, now).ok, false);
  assert.equal(validateGuess({ name: "Priya", guess: "soon" }, now).ok, false);
  assert.equal(validateGuess({ name: "Priya", guess: "2026-10-01T00:00:00Z" }, now).ok, false, "past");
  assert.equal(validateGuess({ name: "Priya", guess: "2040-01-01T00:00:00Z" }, now).ok, false, "too far");
  // Earlier today still counts: it's someone's "any minute now".
  assert.ok(validateGuess({ name: "Priya", guess: "2026-10-08T06:00:00Z" }, now).ok);
});

test("owner actions are close, reopen, or settle with a date", () => {
  assert.deepEqual(validatePoolAction({ action: "close" }), { ok: true, value: { action: "close" } });
  assert.ok(validatePoolAction({ action: "reopen" }).ok);
  const settle = validatePoolAction({ action: "settle", answer: "2026-11-30T04:12:00Z" });
  assert.ok(settle.ok && settle.value.action === "settle" && settle.value.answer.toISOString() === "2026-11-30T04:12:00.000Z");
  assert.equal(validatePoolAction({ action: "settle" }).ok, false);
  assert.equal(validatePoolAction({ action: "delete" }).ok, false);
});

const guess = (name: string, iso: string, created = "2026-10-01T00:00:00Z", tokenHash = name): GuessDoc => ({
  _id: new ObjectId(), slug: "pool", tokenHash, name, guess: new Date(iso), createdAt: new Date(created), updatedAt: new Date(created),
});

test("before settling, guesses run in date order; after, by how close they came", () => {
  const docs = [
    guess("Ana", "2026-12-05T00:00:00Z"),
    guess("Ben", "2026-11-28T00:00:00Z"),
    guess("Cy", "2026-12-01T00:00:00Z"),
  ];
  assert.deepEqual(rankGuesses(docs, undefined, "Ben").map((g) => [g.name, g.mine]), [["Ben", true], ["Cy", false], ["Ana", false]]);

  const ranked = rankGuesses(docs, new Date("2026-12-02T00:00:00Z"), null);
  assert.deepEqual(ranked.map((g) => [g.name, g.place, g.offBySeconds]), [
    ["Cy", 1, 86_400],
    ["Ana", 2, 3 * 86_400],
    ["Ben", 3, 4 * 86_400],
  ]);
});

test("ties share first place", () => {
  const docs = [guess("Ana", "2026-12-01T00:00:00Z", "2026-10-02T00:00:00Z"), guess("Ben", "2026-12-03T00:00:00Z"), guess("Cy", "2026-12-05T00:00:00Z")];
  const ranked = rankGuesses(docs, new Date("2026-12-02T00:00:00Z"), null);
  assert.deepEqual(ranked.map((g) => [g.name, g.place]), [["Ben", 1], ["Ana", 1], ["Cy", 3]]);
});

test("the pool switch is explicit; older apps that leave it out change nothing", () => {
  assert.equal(poolFlag({ title: "x", pool: true }), true);
  assert.equal(poolFlag({ title: "x", pool: false }), false);
  assert.equal(poolFlag({ title: "x" }), undefined);
  assert.equal(poolFlag(null), undefined);
});
