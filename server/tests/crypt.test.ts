import assert from "node:assert/strict";
import { test } from "node:test";
import { floatingAsUTC, isCurrent, validateCryptEntry } from "../src/lib/crypt.ts";
import { viewerTarget } from "../src/lib/time.ts";

test("entries need one kind of time, a known category and scene", () => {
  const base = { slug: "new-year-2027", title: "New Year 2027", details: "", category: "holidays", scene: "confetti" };
  assert.ok(validateCryptEntry({ ...base, local: "2027-01-01T00:00:00" }).ok);
  assert.ok(validateCryptEntry({ ...base, at: "2026-12-21T20:50:00Z" }).ok);
  assert.equal(validateCryptEntry({ ...base }).ok, false, "no time");
  assert.equal(validateCryptEntry({ ...base, local: "2027-01-01T00:00:00", at: "2027-01-01T00:00:00Z" }).ok, false);
  assert.equal(validateCryptEntry({ ...base, at: "2027-01-01T00:00:00" }).ok, false, "exact needs a zone");
  assert.equal(validateCryptEntry({ ...base, local: "2027-01-01" }).ok, false);
  assert.equal(validateCryptEntry({ ...base, local: "2027-01-01T00:00:00", category: "politics" }).ok, false);
  assert.equal(validateCryptEntry({ ...base, local: "2027-01-01T00:00:00", scene: "lava" }).ok, false);
  assert.equal(validateCryptEntry({ ...base, slug: "Bad Slug", local: "2027-01-01T00:00:00" }).ok, false);
});

test("floating times are read on the viewer's clock", () => {
  assert.equal(floatingAsUTC("2027-01-01T00:00:00").toISOString(), "2027-01-01T00:00:00.000Z");
  const local = viewerTarget({ targetDate: "2027-01-01T00:00:00.000Z", floating: "2027-01-01T00:00:00" });
  assert.deepEqual([local.getFullYear(), local.getMonth(), local.getDate(), local.getHours()], [2027, 0, 1, 0]);
  assert.equal(viewerTarget({ targetDate: "2026-12-21T20:50:00.000Z" }).toISOString(), "2026-12-21T20:50:00.000Z");
});

test("entries stay listed until a day after the last time zone reaches them", () => {
  const nye = { targetDate: floatingAsUTC("2027-01-01T00:00:00"), floating: "2027-01-01T00:00:00" };
  assert.ok(isCurrent(nye, new Date("2027-01-02T11:00:00Z")), "still midnight somewhere plus a day");
  assert.ok(!isCurrent(nye, new Date("2027-01-02T13:00:00Z")));
  const solstice = { targetDate: new Date("2026-12-21T20:50:00Z") };
  assert.ok(isCurrent(solstice, new Date("2026-12-22T20:00:00Z")));
  assert.ok(!isCurrent(solstice, new Date("2026-12-22T21:00:00Z")));
});
