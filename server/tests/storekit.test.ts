import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { createPrivateKey, sign, X509Certificate } from "node:crypto";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { verifyTransaction } from "../src/lib/storekit.ts";

// A stand-in for Apple's chain, made with openssl: a root, an intermediate and a leaf carrying the
// same App Store marker extensions, so every check runs for real against a root we pin in the test.
const dir = mkdtempSync(path.join(tmpdir(), "storekit-"));
const ssl = (...args: string[]) => execFileSync("openssl", args, { cwd: dir, stdio: "pipe" });
writeFileSync(path.join(dir, "ext.cnf"), [
  "[intermediate]", "basicConstraints=critical,CA:true", "1.2.840.113635.100.6.2.1=ASN1:NULL",
  "[leaf]", "basicConstraints=critical,CA:false", "1.2.840.113635.100.6.11.1=ASN1:NULL",
  "[root]", "basicConstraints=critical,CA:true",
].join("\n"));
for (const name of ["root", "intermediate", "leaf"]) ssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", `${name}.key`);
ssl("req", "-x509", "-new", "-key", "root.key", "-subj", "/CN=Test Root", "-days", "3650", "-out", "root.pem", "-extensions", "root", "-config", "ext.cnf");
ssl("req", "-new", "-key", "intermediate.key", "-subj", "/CN=Test Intermediate", "-out", "intermediate.csr");
ssl("x509", "-req", "-in", "intermediate.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial", "-days", "3650",
  "-extfile", "ext.cnf", "-extensions", "intermediate", "-out", "intermediate.pem");
ssl("req", "-new", "-key", "leaf.key", "-subj", "/CN=Test Leaf", "-out", "leaf.csr");
ssl("x509", "-req", "-in", "leaf.csr", "-CA", "intermediate.pem", "-CAkey", "intermediate.key", "-CAcreateserial", "-days", "3650",
  "-extfile", "ext.cnf", "-extensions", "leaf", "-out", "leaf.pem");

const pem = (name: string) => readFileSync(path.join(dir, name), "utf8");
const der = (name: string) => new X509Certificate(pem(name)).raw.toString("base64");
const root = new X509Certificate(pem("root.pem"));
const leafKey = createPrivateKey(pem("leaf.key"));
const chain = [der("leaf.pem"), der("intermediate.pem"), der("root.pem")];

const transaction = {
  transactionId: "2000000123456789", originalTransactionId: "2000000123456789", bundleId: "com.countdownula.app",
  productId: "com.countdownula.app.hostpass", type: "Consumable", purchaseDate: Date.now(), signedDate: Date.now(),
  environment: "Production",
};

function jws(payload: object, x5c = chain, key = leafKey): string {
  const b64 = (o: object) => Buffer.from(JSON.stringify(o)).toString("base64url");
  const signing = `${b64({ alg: "ES256", x5c })}.${b64(payload)}`;
  return `${signing}.${sign("sha256", Buffer.from(signing), { key, dsaEncoding: "ieee-p1363" }).toString("base64url")}`;
}

const pinned = { rootFingerprint: root.fingerprint256 };

test("a properly signed Host Pass verifies", () => {
  const result = verifyTransaction(jws(transaction), pinned);
  assert.ok(result.ok, result.ok ? "" : result.error);
  assert.equal(result.value.transactionId, "2000000123456789");
  assert.ok(verifyTransaction(jws({ ...transaction, environment: "Sandbox" }), pinned).ok, "App Review buys in the sandbox");
});

test("anything not rooted in the pinned certificate is refused", () => {
  const result = verifyTransaction(jws(transaction));
  assert.ok(!result.ok);
  assert.match(result.error, /Not signed by Apple/, "Apple's real root is the default");
});

test("tampering, the wrong key, or a short chain fails", () => {
  const good = jws(transaction);
  const [h, , s] = good.split(".");
  const forged = `${h}.${Buffer.from(JSON.stringify({ ...transaction, productId: "com.countdownula.app.hostpass", transactionId: "999" })).toString("base64url")}.${s}`;
  assert.match((verifyTransaction(forged, pinned) as { error: string }).error, /signature/);
  assert.match((verifyTransaction(jws(transaction, chain, createPrivateKey(pem("root.key"))), pinned) as { error: string }).error, /signature/);
  assert.match((verifyTransaction(jws(transaction, chain.slice(0, 2)), pinned) as { error: string }).error, /chain/);
  assert.match((verifyTransaction("not.a.jws", pinned) as { error: string }).error, /signed transaction/);
});

test("the payload has to be our Host Pass, unrefunded", () => {
  const error = (p: object) => (verifyTransaction(jws({ ...transaction, ...p }), pinned) as { error: string }).error;
  assert.match(error({ bundleId: "com.example.other" }), /another app/);
  assert.match(error({ productId: "com.countdownula.app.unlimited" }), /isn't a Host Pass/);
  assert.match(error({ type: "Non-Consumable" }), /type/);
  assert.match(error({ revocationDate: Date.now() }), /refunded/);
  assert.match(error({ environment: "Xcode" }), /environment/, "Xcode only when allowed");
});

test("Xcode's local StoreKit testing is accepted only when asked for", () => {
  const selfSigned = jws({ ...transaction, environment: "Xcode" }, [der("leaf.pem")]);
  assert.ok(!verifyTransaction(selfSigned, pinned).ok);
  assert.ok(verifyTransaction(selfSigned, { ...pinned, allowXcode: true }).ok);
});
