import assert from "node:assert/strict";
import { test } from "node:test";
import { presentPhase, qrPath, roomLink } from "../src/lib/present.ts";

test("the room's QR code is a square path with a quiet zone", () => {
  const { size, path } = qrPath("https://countdowncula.com/c/abcd2345?src=present");
  assert.ok(size >= 25 + 4, "Version 2 or larger, plus a two-module margin");
  assert.match(path, /^M\d+ \d+h\d+v1h-\d+z/);
  // The top-left finder pattern starts two modules in: a run of seven dark modules.
  assert.ok(path.startsWith("M2 2h7v1h-7z"));
});

test("the room link keeps the live link and tags it", () => {
  assert.equal(roomLink("https://countdowncula.com/c/sarah-and-tom"), "https://countdowncula.com/c/sarah-and-tom?src=present");
  assert.equal(roomLink("https://countdowncula.com/c/x1y2z3?src=wallet"), "https://countdowncula.com/c/x1y2z3?src=present");
});

test("the last ten seconds show one number, then zero", () => {
  const zero = new Date("2027-01-01T05:00:00Z");
  const at = (s: number) => new Date(zero.getTime() - s * 1000);
  assert.deepEqual(presentPhase(at(11), zero, false), { phase: "counting", finalSecond: null });
  assert.deepEqual(presentPhase(at(10), zero, false), { phase: "final", finalSecond: 10 });
  assert.deepEqual(presentPhase(at(0.2), zero, false), { phase: "final", finalSecond: 1 });
  assert.deepEqual(presentPhase(at(0), zero, false), { phase: "zero", finalSecond: null });
  assert.deepEqual(presentPhase(at(5), zero, true), { phase: "counting", finalSecond: null }, "A count-up never ends");
});
