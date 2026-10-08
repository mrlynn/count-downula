import assert from "node:assert/strict";
import { generateKeyPairSync, verify } from "node:crypto";
import { test } from "node:test";
import { providerToken, sendBackgroundPush, type Transport } from "../src/lib/apns.ts";

const { privateKey, publicKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
const pem = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const env = { APNS_KEY_ID: "ABC123DEFG", APNS_TEAM_ID: "YZ36Z8GSEN", APNS_PRIVATE_KEY: pem.replace(/\n/g, "\\n") };

test("the provider token is an ES256 JWT APNs can verify", () => {
  const jwt = providerToken(env, Date.UTC(2026, 9, 8, 12));
  const [header, claims, signature] = jwt.split(".");
  assert.deepEqual(JSON.parse(Buffer.from(header, "base64url").toString()), { alg: "ES256", kid: "ABC123DEFG" });
  assert.deepEqual(JSON.parse(Buffer.from(claims, "base64url").toString()), { iss: "YZ36Z8GSEN", iat: 1791460800 });
  const ok = verify("sha256", Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: "ieee-p1363" },
    Buffer.from(signature, "base64url"));
  assert.ok(ok, "Signature verifies with the matching public key");
  assert.equal(providerToken(env, Date.UTC(2026, 9, 8, 12, 30)), jwt, "Reused within 50 minutes");
});

test("background pushes go to the right host and report dead tokens", async () => {
  const sent: { host: string; path: string; headers: Record<string, string>; body: string }[] = [];
  const transport: Transport = async (host, path, headers, body) => {
    sent.push({ host, path, headers, body });
    if (path.endsWith("dead")) return { status: 410, reason: "Unregistered" };
    if (path.endsWith("flaky")) return { status: 500 };
    return { status: 200 };
  };
  const outcomes = await sendBackgroundPush(
    [{ token: "live", sandbox: true }, { token: "dead", sandbox: false }, { token: "flaky", sandbox: false }],
    "cb4TV7jV", { env, transport });
  assert.deepEqual(Object.fromEntries(outcomes), { live: "sent", dead: "gone", flaky: "failed" });
  assert.equal(sent.find((s) => s.path.endsWith("live"))?.host, "api.sandbox.push.apple.com");
  assert.equal(sent.find((s) => s.path.endsWith("dead"))?.host, "api.push.apple.com");
  const first = sent[0];
  assert.equal(first.headers["apns-push-type"], "background");
  assert.equal(first.headers["apns-priority"], "5");
  assert.equal(first.headers["apns-topic"], "com.countdownula.app");
  assert.deepEqual(JSON.parse(first.body), { aps: { "content-available": 1 }, countdownula: { slug: "cb4TV7jV" } });
});

test("without a key, nothing is sent", async () => {
  let calls = 0;
  const outcomes = await sendBackgroundPush([{ token: "live", sandbox: true }], "x", {
    env: {}, transport: async () => (calls++, { status: 200 }) });
  assert.equal(outcomes.size, 0);
  assert.equal(calls, 0);
});
