import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { unzipSync } from "fflate";
import forge from "node-forge";
import { authenticationToken, authorized, buildPkpass, isoInZone, manifest, passJSON } from "../src/lib/wallet.ts";

const doc = {
  slug: "cb4TV7jV", ownerTokenHash: "", title: "Maya & Theo's Wedding", details: "Napa, ceremony at 4.",
  targetDate: new Date("2026-11-14T21:00:00Z"), createdAt: new Date("2026-09-01T00:00:00Z"),
  updatedAt: new Date("2026-10-08T00:00:00Z"), publishedAt: new Date("2026-09-01T00:00:00Z"),
  kind: "event" as const, timeZone: "America/Los_Angeles",
  style: { accent: { red: 0.88, green: 0.27, blue: 0.48, opacity: 1 } }, milestones: [], hasPhoto: false,
  visibility: "link" as const, stats: { views: 0 },
};

test("times are written in the owner's zone, including across daylight saving", () => {
  assert.equal(isoInZone(new Date("2026-11-14T21:00:00Z"), "America/Los_Angeles"), "2026-11-14T13:00:00-08:00");
  assert.equal(isoInZone(new Date("2026-07-04T21:00:00Z"), "America/Los_Angeles"), "2026-07-04T14:00:00-07:00");
  assert.equal(isoInZone(new Date("2026-07-04T21:00:00Z"), "Asia/Kolkata"), "2026-07-05T02:30:00+05:30");
  assert.equal(isoInZone(new Date("2026-07-04T21:00:00Z"), "Not/AZone"), "2026-07-04T21:00:00+00:00");
});

test("the pass is an event ticket that surfaces on the day and links back to the page", () => {
  process.env.ADMIN_SECRET = "secret";
  const pass = passJSON(doc, { url: "https://go.countdowncula.com/c/cb4TV7jV", webServiceURL: "https://go.countdowncula.com/api/wallet", memberCount: 3 });
  assert.equal(pass.passTypeIdentifier, "pass.com.countdownula.app");
  assert.equal(pass.teamIdentifier, "YZ36Z8GSEN");
  assert.equal(pass.serialNumber, "cb4TV7jV");
  assert.equal(pass.relevantDate, "2026-11-14T13:00:00-08:00");
  assert.equal(pass.expirationDate, "2026-11-15T13:00:00-08:00");
  assert.equal(pass.labelColor, "rgb(224, 69, 122)");
  assert.equal(pass.barcodes[0].message, "https://go.countdowncula.com/c/cb4TV7jV");
  assert.equal(pass.eventTicket.primaryFields[0].value, "Maya & Theo's Wedding");
  assert.ok(pass.eventTicket.secondaryFields.some((f: any) => f.isRelative), "A field Wallet keeps counting down");
  assert.equal(pass.eventTicket.auxiliaryFields[0].value, "3 people");
  assert.equal(pass.authenticationToken, authenticationToken("cb4TV7jV", "secret"));
  assert.ok(pass.authenticationToken.length >= 16, "Wallet needs at least 16 characters");
});

test("only Wallet holding the pass's own token gets in", () => {
  const token = authenticationToken("cb4TV7jV", "secret");
  assert.ok(authorized(`ApplePass ${token}`, "cb4TV7jV", "secret"));
  assert.ok(!authorized(`ApplePass ${token}`, "otherSlug", "secret"));
  assert.ok(!authorized(`Bearer ${token}`, "cb4TV7jV", "secret"));
  assert.ok(!authorized(null, "cb4TV7jV", "secret"));
  assert.ok(!authorized(`ApplePass ${authenticationToken("x", "")}`, "x", ""), "No secret, no access");
});

test("the pkpass has a matching manifest and a signature OpenSSL accepts", () => {
  // A throwaway CA standing in for Apple's WWDR, and a pass certificate it issued.
  const make = (subject: string, issuerKeys?: forge.pki.rsa.KeyPair, issuerCert?: forge.pki.Certificate) => {
    const keys = forge.pki.rsa.generateKeyPair(2048);
    const cert = forge.pki.createCertificate();
    cert.publicKey = keys.publicKey;
    cert.serialNumber = String(Math.floor(Math.random() * 1e9));
    cert.validity.notBefore = new Date(Date.now() - 86_400_000);
    cert.validity.notAfter = new Date(Date.now() + 86_400_000);
    cert.setSubject([{ name: "commonName", value: subject }]);
    cert.setIssuer((issuerCert ?? cert).subject.attributes);
    if (!issuerCert) cert.setExtensions([{ name: "basicConstraints", cA: true }, { name: "keyUsage", keyCertSign: true, digitalSignature: true }]);
    cert.sign((issuerKeys ?? keys).privateKey, forge.md.sha256.create());
    return { keys, cert };
  };
  const ca = make("Test WWDR");
  const passCert = make("Pass Type ID: pass.com.countdownula.app", ca.keys, ca.cert);
  const env = {
    PASS_CERT_PEM: forge.pki.certificateToPem(passCert.cert),
    PASS_KEY_PEM: forge.pki.privateKeyToPem(passCert.keys.privateKey),
    PASS_WWDR_PEM: forge.pki.certificateToPem(ca.cert),
  };
  const images = { "icon.png": new Uint8Array([1, 2, 3]), "icon@2x.png": new Uint8Array([4, 5]) };
  const files = unzipSync(buildPkpass({ formatVersion: 1, serialNumber: "x" }, images, env));
  assert.deepEqual(Object.keys(files).sort(), ["icon.png", "icon@2x.png", "manifest.json", "pass.json", "signature"]);
  const listed = JSON.parse(Buffer.from(files["manifest.json"]).toString());
  assert.deepEqual(listed, manifest({ "pass.json": files["pass.json"], ...images }));

  const dir = mkdtempSync(path.join(tmpdir(), "pkpass-"));
  writeFileSync(path.join(dir, "manifest.json"), files["manifest.json"]);
  writeFileSync(path.join(dir, "signature"), files.signature);
  writeFileSync(path.join(dir, "ca.pem"), env.PASS_WWDR_PEM);
  const verify = spawnSync("openssl", ["smime", "-verify", "-binary", "-inform", "DER", "-in", path.join(dir, "signature"),
    "-content", path.join(dir, "manifest.json"), "-CAfile", path.join(dir, "ca.pem"), "-purpose", "any", "-out", "/dev/null"]);
  assert.equal(verify.status, 0, verify.stderr.toString());
});
