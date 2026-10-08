// End-to-end check of Wallet passes against a running server that has PASS_* certificates set:
// download, contents, and Wallet's web service (register, list, fetch, unregister).
// Usage: BASE=http://localhost:4300 node scripts/smoke-wallet.mjs
import assert from "node:assert/strict";
import { unzipSync } from "fflate";

const base = process.env.BASE ?? "http://localhost:4300";
const passType = "pass.com.countdownula.app";
let res = await fetch(`${base}/api/countdowns`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({
  countdown: { title: "Wallet smoke", details: "Back of the pass.", targetDate: "2026-11-14T21:00:00Z", createdAt: "2026-09-01T00:00:00Z",
    kind: "event", timeZone: "America/Los_Angeles", style: { background: { scene: { _0: "blossoms" } }, font: "serif", weight: "bold" }, milestones: [] } }) });
assert.equal(res.status, 201);
const { slug, ownerToken } = await res.json();

res = await fetch(`${base}/c/${slug}/pass`);
assert.equal(res.status, 200, await res.clone().text());
assert.equal(res.headers.get("content-type"), "application/vnd.apple.pkpass");
const files = unzipSync(new Uint8Array(await res.arrayBuffer()));
const pass = JSON.parse(Buffer.from(files["pass.json"]).toString());
for (const name of ["icon.png", "icon@2x.png", "logo@2x.png", "strip@2x.png", "manifest.json", "signature"]) assert.ok(files[name], name);
assert.equal(pass.serialNumber, slug);
assert.equal(pass.relevantDate, "2026-11-14T13:00:00-08:00");
console.log("pass ok:", Object.keys(files).length, "files");
if (process.env.OUT) (await import("node:fs")).writeFileSync(process.env.OUT, Buffer.from(files["strip@2x.png"]));

const auth = { authorization: `ApplePass ${pass.authenticationToken}`, "content-type": "application/json" };
const reg = `${base}/api/wallet/v1/devices/device123/registrations/${passType}/${slug}`;
assert.equal((await fetch(reg, { method: "POST", headers: { ...auth, authorization: "ApplePass nope" }, body: JSON.stringify({ pushToken: "ab".repeat(32) }) })).status, 401);
assert.equal((await fetch(reg, { method: "POST", headers: auth, body: JSON.stringify({ pushToken: "ab".repeat(32) }) })).status, 201);
assert.equal((await fetch(reg, { method: "POST", headers: auth, body: JSON.stringify({ pushToken: "ab".repeat(32) }) })).status, 200);
res = await fetch(`${base}/api/wallet/v1/devices/device123/registrations/${passType}`);
const listed = await res.json();
assert.deepEqual(listed.serialNumbers, [slug]);
assert.equal((await fetch(`${base}/api/wallet/v1/devices/device123/registrations/${passType}?passesUpdatedSince=${listed.lastUpdated}`)).status, 204);
res = await fetch(`${base}/api/wallet/v1/passes/${passType}/${slug}`, { headers: auth });
assert.equal(res.status, 200);
assert.equal((await fetch(`${base}/api/wallet/v1/passes/${passType}/${slug}`, { headers: { ...auth, "if-modified-since": res.headers.get("last-modified") } })).status, 304);
assert.equal((await fetch(`${base}/api/wallet/v1/passes/${passType}/${slug}`)).status, 401);
assert.equal((await fetch(reg, { method: "DELETE", headers: auth })).status, 200);
assert.equal((await fetch(`${base}/api/wallet/v1/log`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ logs: ["test"] }) })).status, 200);
console.log("web service ok");

assert.equal((await fetch(`${base}/api/countdowns/${slug}`, { method: "DELETE", headers: { authorization: `Bearer ${ownerToken}` } })).status, 204);
console.log("wallet smoke ok");
