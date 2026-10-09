import assert from "node:assert/strict";
import { test } from "node:test";
import { isOpen, looksLikeVideo, mediaPathsOf, photoPathsOf, reportSignature, reportSignatureValid, validateContribution } from "../src/lib/coffin.ts";

const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10]).toString("base64");

test("a contribution needs a name and a note or photo", () => {
  assert.equal(validateContribution({ name: "", text: "hi" }).ok, false);
  assert.equal(validateContribution({ name: "Ana", text: "" }).ok, false);
  assert.deepEqual(validateContribution({ name: " Ana ", text: " Happy birthday! " }), {
    ok: true, value: { name: "Ana", text: "Happy birthday!", photos: [] } });
  const photoOnly = validateContribution({ name: "Ana", photo: jpeg });
  assert.ok(photoOnly.ok && photoOnly.value.photos[0]?.length === 6, "Older apps send one photo");
});

test("hosted countdowns take several photos per note; others take one", () => {
  const four = validateContribution({ name: "Ana", photos: [jpeg, jpeg, jpeg, jpeg] }, 4);
  assert.ok(four.ok && four.value.photos.length === 4);
  const tooMany = validateContribution({ name: "Ana", photos: [jpeg, jpeg] });
  assert.ok(!tooMany.ok && /Host Pass/.test(tooMany.error));
  assert.equal(validateContribution({ name: "Ana", photos: [jpeg, jpeg, jpeg, jpeg, jpeg] }, 4).ok, false);
  assert.equal(validateContribution({ name: "Ana", photos: [jpeg, 7] }, 4).ok, false);
});

test("a note's media paths cover old and new notes", () => {
  assert.deepEqual(photoPathsOf({ photoPath: "a.jpg" }), ["a.jpg"]);
  assert.deepEqual(photoPathsOf({ photoPath: "a.jpg", photoPaths: ["a.jpg", "a-1.jpg"] }), ["a.jpg", "a-1.jpg"]);
  assert.deepEqual(mediaPathsOf({ photoPath: "a.jpg", photoPaths: ["a.jpg", "a-1.jpg"], videoPath: "a.mp4" }), ["a.jpg", "a-1.jpg", "a.mp4"]);
  assert.deepEqual(mediaPathsOf({}), []);
});

test("limits and formats are enforced", () => {
  assert.equal(validateContribution({ name: "x".repeat(41), text: "hi" }).ok, false);
  assert.equal(validateContribution({ name: "Ana", text: "x".repeat(501) }).ok, false);
  assert.equal(validateContribution({ name: "Ana", photo: Buffer.from("PNG...").toString("base64") }).ok, false, "JPEG only");
  assert.equal(validateContribution({ name: "Ana", photo: Buffer.alloc(401 * 1024, 0xff).toString("base64") }).ok, false);
  assert.equal(validateContribution(null).ok, false);
});

test("the coffin opens at zero, not a moment before", () => {
  const targetDate = new Date("2026-11-14T21:00:00Z");
  assert.equal(isOpen({ targetDate }, new Date("2026-11-14T20:59:59Z")), false);
  assert.equal(isOpen({ targetDate }, new Date("2026-11-14T21:00:00Z")), true);
});

test("review links only work with the right signature and a secret set", () => {
  const sig = reportSignature("65f0c0ffee0000000000abcd", "secret");
  assert.ok(reportSignatureValid("65f0c0ffee0000000000abcd", sig, "secret"));
  assert.ok(!reportSignatureValid("65f0c0ffee0000000000abce", sig, "secret"), "Bound to the ID");
  assert.ok(!reportSignatureValid("65f0c0ffee0000000000abcd", sig, "other"));
  assert.ok(!reportSignatureValid("65f0c0ffee0000000000abcd", reportSignature("65f0c0ffee0000000000abcd", ""), ""),
    "No secret, no access");
});

test("videos are recognized by their ftyp box", () => {
  const mp4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from("ftypmp42"), Buffer.alloc(8)]);
  assert.ok(looksLikeVideo(mp4));
  assert.ok(!looksLikeVideo(Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0, 0x10, 0, 0, 0, 0, 0, 0, 0])), "A JPEG isn't");
  assert.ok(!looksLikeVideo(Buffer.from("ftyp")), "Too short");
});
