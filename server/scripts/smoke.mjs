// End-to-end check against a running server: publish, read, render, edit, unpublish.
// Usage: BASE=http://localhost:4300 node scripts/smoke.mjs
import assert from "node:assert/strict";

const base = process.env.BASE ?? "http://localhost:4300";
const jpeg = Buffer.from(
  "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==",
  "base64",
);
const countdown = {
  title: "Halloween",
  details: "Costumes ready.",
  targetDate: "2026-11-01T01:00:00Z",
  createdAt: "2026-10-01T00:00:00Z",
  kind: "event",
  timeZone: "America/New_York",
  style: { background: { gradient: { _0: { stops: [{ red: 0.97, green: 0.21, blue: 0 }, { red: 0.42, green: 0.05, blue: 0.11 }], angle: 120 } } }, font: "serif", weight: "bold" },
  milestones: [],
};

const json = (body) => ({ method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) });

let res = await fetch(`${base}/api/countdowns`, json({ countdown, photo: jpeg.toString("base64") }));
assert.equal(res.status, 201, await res.clone().text());
const created = await res.json();
console.log("published", created.url);
assert.ok(created.ownerToken && created.slug);

res = await fetch(`${base}/api/countdowns/${created.slug}`);
assert.equal(res.status, 200);
assert.equal((await res.json()).countdown.title, "Halloween");

res = await fetch(`${base}/c/${created.slug}`);
assert.equal(res.status, 200);
const html = await res.text();
assert.match(html, /og:image/);
assert.match(html, /Halloween/);
const og = html.match(/property="og:image" content="([^"]+)"/)[1].replaceAll("&amp;", "&");
console.log("og:image", og);

res = await fetch(`${base}/c/${created.slug}/og`);
assert.equal(res.status, 200);
assert.equal(res.headers.get("content-type"), "image/png");
const png = Buffer.from(await res.arrayBuffer());
console.log("og bytes", png.length);
if (process.env.OG_OUT) (await import("node:fs")).writeFileSync(process.env.OG_OUT, png);

res = await fetch(`${base}/c/${created.slug}/photo`);
assert.equal(res.headers.get("content-type"), "image/jpeg");

const put = (token, body) => fetch(`${base}/api/countdowns/${created.slug}`, {
  method: "PUT",
  headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
  body: JSON.stringify(body),
});
assert.equal((await put("wrong", { countdown })).status, 403);
res = await put(created.ownerToken, { countdown: { ...countdown, title: "Halloween party" }, photo: null });
assert.equal(res.status, 200);
const updated = (await res.json()).countdown;
assert.equal(updated.title, "Halloween party");
assert.equal(updated.hasPhoto, false);

assert.equal((await fetch(`${base}/api/countdowns`, json({ countdown: { title: "" } }))).status, 422);

// Members: join twice, see the count on the API and the page, leave once.
const join = () => fetch(`${base}/api/countdowns/${created.slug}/members`, { method: "POST" });
res = await join();
assert.equal(res.status, 201, await res.clone().text());
const member = await res.json();
assert.ok(member.memberToken);
assert.equal((await (await join()).json()).memberCount, 2);
assert.equal((await (await fetch(`${base}/api/countdowns/${created.slug}?fresh=${Date.now()}`)).json()).memberCount, 2);
assert.match(await (await fetch(`${base}/c/${created.slug}`)).text(), /2 people are counting down/);
res = await fetch(`${base}/api/countdowns/${created.slug}/members`, { method: "DELETE", headers: { authorization: `Bearer ${member.memberToken}` } });
assert.equal(res.status, 204);
assert.equal((await (await fetch(`${base}/api/countdowns/${created.slug}?fresh=${Date.now()}`)).json()).memberCount, 1);
assert.equal((await fetch(`${base}/api/countdowns/zzzzzzzz/members`, { method: "POST" })).status, 404);
console.log("members ok");

res = await fetch(`${base}/.well-known/apple-app-site-association`);
assert.equal(res.status, 200);
assert.match(res.headers.get("content-type"), /json/);
assert.deepEqual((await res.json()).applinks.details[0].appIDs, ["YZ36Z8GSEN.com.countdownula.app"]);
console.log("aasa ok");

res = await fetch(`${base}/api/countdowns/${created.slug}`, { method: "DELETE", headers: { authorization: `Bearer ${created.ownerToken}` } });
assert.equal(res.status, 204);
assert.equal((await fetch(`${base}/c/${created.slug}`)).status, 404);
console.log("smoke ok");
