// End-to-end check of the sealed coffin against a running server with a Blob store:
// sealed before zero, open after, photos, reports, owner removal, purge on unpublish.
// Usage: BASE=http://localhost:4300 node scripts/smoke-coffin.mjs
import assert from "node:assert/strict";

const base = process.env.BASE ?? "http://localhost:4300";
const jpeg = Buffer.from(
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==",
  "base64",
);
const opensIn = 8_000;
const json = (method, body, token) => ({
  method, headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
  body: body === undefined ? undefined : JSON.stringify(body),
});
const target = new Date(Date.now() + opensIn).toISOString();
let res = await fetch(`${base}/api/countdowns`, json("POST", { countdown: {
  title: "Coffin smoke", details: "", targetDate: target, createdAt: new Date(Date.now() - 86_400_000).toISOString(),
  kind: "event", timeZone: "UTC", style: {}, milestones: [] } }));
assert.equal(res.status, 201, await res.clone().text());
const { slug, ownerToken } = await res.json();
const coffin = `${base}/api/countdowns/${slug}/coffin`;
const member = (await (await fetch(`${base}/api/countdowns/${slug}/members`, { method: "POST" })).json()).memberToken;

// Sealed: strangers can't add, members and the owner can.
assert.equal((await fetch(coffin, json("POST", { name: "Nobody", text: "hi" }))).status, 403);
res = await fetch(coffin, json("POST", { name: "Ana", text: "Happy birthday!", photo: jpeg.toString("base64") }, member));
assert.equal(res.status, 201, await res.clone().text());
const anas = await res.json();
assert.equal(anas.mine, true);
res = await fetch(coffin, json("POST", { name: "Owner", text: "Surprise." }, ownerToken));
assert.equal(res.status, 201);
const owners = await res.json();

// Before zero: a count for everyone, only their own for each person, photos stay sealed.
let view = await (await fetch(coffin)).json();
assert.deepEqual([view.open, view.sealedCount, view.contributions.length], [false, 2, 0]);
view = await (await fetch(coffin, json("GET", undefined, member))).json();
assert.deepEqual(view.contributions.map((c) => c.name), ["Ana"]);
assert.equal((await fetch(`${coffin}/${owners.id}/photo`, json("GET", undefined, member))).status, 404, "No photo, no peek");
assert.equal((await fetch(`${coffin}/${anas.id}/photo`, json("GET", undefined, ownerToken))).status, 403, "Still sealed");
assert.equal((await fetch(`${coffin}/${anas.id}/photo`, json("GET", undefined, member))).status, 200, "Your own photo");
assert.match(await (await fetch(`${base}/c/${slug}`)).text(), /2 sealed in the coffin/);
console.log("sealed ok");

// After zero: everything, for people in the countdown.
await new Promise((r) => setTimeout(r, opensIn + 1_000));
view = await (await fetch(coffin, json("GET", undefined, member))).json();
assert.deepEqual([view.open, view.contributions.length], [true, 2]);
assert.equal((await (await fetch(coffin)).json()).contributions.length, 0, "Strangers still see nothing");
res = await fetch(`${coffin}/${anas.id}/photo`, json("GET", undefined, ownerToken));
assert.equal(res.status, 200);
assert.equal(res.headers.get("content-type"), "image/jpeg");
assert.equal((await fetch(coffin, json("POST", { name: "Late", text: "too late" }, member))).status, 409);
console.log("open ok");

// Reports and removal: members can only remove their own, owners anything.
assert.equal((await fetch(`${coffin}/${anas.id}/report`, json("POST", undefined, ownerToken))).status, 204);
assert.equal((await fetch(`${coffin}/${owners.id}`, json("DELETE", undefined, member))).status, 403);
assert.equal((await fetch(`${coffin}/${anas.id}`, json("DELETE", undefined, ownerToken))).status, 204);
view = await (await fetch(coffin, json("GET", undefined, member))).json();
assert.deepEqual(view.contributions.map((c) => c.name), ["Owner"]);
assert.equal((await fetch(`${coffin}/${anas.id}/photo`, json("GET", undefined, member))).status, 404, "Removed photo is gone");
console.log("moderation ok");

res = await fetch(`${base}/api/countdowns/${slug}`, json("DELETE", undefined, ownerToken));
assert.equal(res.status, 204);
console.log("coffin smoke ok");
