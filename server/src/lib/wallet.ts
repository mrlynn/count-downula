// Apple Wallet passes: a countdown as an event ticket that surfaces on the Lock Screen as the day
// approaches, with a QR code back to its live page. Signing needs the Pass Type ID certificate:
//   PASS_CERT_PEM    the certificate (pass.com.countdownula.app), PEM
//   PASS_KEY_PEM     its private key, PEM (PASS_KEY_PASSPHRASE if it's encrypted)
//   PASS_WWDR_PEM    Apple's WWDR intermediate certificate (G4), PEM
// Without them, passes can't be built.
import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { zipSync } from "fflate";
import forge from "node-forge";
import type { CountdownDoc } from "./countdowns.ts";

export const PASS_TYPE_ID = process.env.PASS_TYPE_ID ?? "pass.com.countdownula.app";
export const TEAM_ID = "YZ36Z8GSEN";

export type WalletEnv = Record<string, string | undefined>;

export function walletConfigured(env: WalletEnv = process.env): boolean {
  return Boolean(env.PASS_CERT_PEM && env.PASS_KEY_PEM && env.PASS_WWDR_PEM);
}

/** The token Wallet sends back as "ApplePass <token>"; derived, so nothing extra is stored. */
export function authenticationToken(serial: string, secret = process.env.ADMIN_SECRET ?? ""): string {
  return createHmac("sha256", secret).update(`wallet:${serial}`).digest("base64url");
}

export function authorized(header: string | null, serial: string, secret = process.env.ADMIN_SECRET ?? ""): boolean {
  const match = /^ApplePass\s+(.+)$/.exec(header ?? "");
  if (!match || !secret) return false;
  const a = Buffer.from(match[1]);
  const b = Buffer.from(authenticationToken(serial, secret));
  return a.length === b.length && timingSafeEqual(a, b);
}

/** "2026-11-14T13:00:00-08:00": the target in the owner's own zone, so the pass shows their time. */
export function isoInZone(date: Date, timeZone: string): string {
  let zone = timeZone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: zone });
  } catch {
    zone = "UTC";
  }
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", {
      timeZone: zone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit",
      hour: "2-digit", minute: "2-digit", second: "2-digit",
    }).formatToParts(date).map((p) => [p.type, p.value]),
  );
  const local = Date.UTC(+parts.year, +parts.month - 1, +parts.day, +parts.hour, +parts.minute, +parts.second);
  const offsetMinutes = Math.round((local - Math.floor(date.getTime() / 1000) * 1000) / 60_000);
  const sign = offsetMinutes < 0 ? "-" : "+";
  const abs = Math.abs(offsetMinutes);
  const offset = `${sign}${String(Math.floor(abs / 60)).padStart(2, "0")}:${String(abs % 60).padStart(2, "0")}`;
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}${offset}`;
}

type Rgba = { red?: number; green?: number; blue?: number };
const rgb = (c: Rgba | undefined, fallback: string) =>
  c && typeof c.red === "number"
    ? `rgb(${Math.round(c.red * 255)}, ${Math.round((c.green ?? 0) * 255)}, ${Math.round((c.blue ?? 0) * 255)})`
    : fallback;

export interface PassOptions {
  url: string;
  webServiceURL: string;
  memberCount: number;
}

/** pass.json for a countdown. Pure, for tests. */
export function passJSON(doc: CountdownDoc, { url, webServiceURL, memberCount }: PassOptions) {
  const when = isoInZone(doc.targetDate, doc.timeZone);
  // A floating local time ("midnight wherever you are") reads the same wall-clock time on every device.
  const floating = Boolean(doc.floating);
  const accent = (doc.style as { accent?: Rgba }).accent;
  const backFields: object[] = [];
  if (doc.details) backFields.push({ key: "details", label: "About", value: doc.details });
  backFields.push(
    { key: "link", label: "Live countdown", value: url, attributedValue: `<a href="${url}">${url}</a>` },
    { key: "app", label: "Count Downcula", value: "Count down together on your Lock Screen, watch and menu bar." },
  );
  return {
    formatVersion: 1,
    passTypeIdentifier: PASS_TYPE_ID,
    teamIdentifier: TEAM_ID,
    serialNumber: doc.slug,
    organizationName: "Count Downcula",
    description: `${doc.title} countdown`,
    foregroundColor: "rgb(250, 242, 227)",
    backgroundColor: "rgb(20, 6, 10)",
    labelColor: rgb(accent, "rgb(217, 23, 58)"),
    // Brings the pass to the Lock Screen as the day approaches.
    relevantDate: when,
    relevantDates: [{ startDate: isoInZone(new Date(doc.targetDate.getTime() - 4 * 3_600_000), doc.timeZone), endDate: when }],
    expirationDate: isoInZone(new Date(doc.targetDate.getTime() + 24 * 3_600_000), doc.timeZone),
    webServiceURL,
    authenticationToken: authenticationToken(doc.slug),
    barcodes: [{ format: "PKBarcodeFormatQR", message: url, messageEncoding: "iso-8859-1", altText: "Scan to count down together" }],
    eventTicket: {
      headerFields: [{ key: "date", label: "WHEN", value: when, dateStyle: "PKDateStyleMedium", ignoresTimeZone: true }],
      primaryFields: [{ key: "title", value: doc.title }],
      secondaryFields: [
        { key: "time", label: "AT", value: when, dateStyle: "PKDateStyleNone", timeStyle: "PKDateStyleShort", ignoresTimeZone: true },
        // Wallet keeps this current on its own: "in 5 days", "in 3 hours".
        { key: "countdown", label: "COUNTDOWN", value: when, isRelative: true, dateStyle: "PKDateStyleShort", timeStyle: "PKDateStyleShort",
          ...(floating ? { ignoresTimeZone: true } : {}) },
      ],
      auxiliaryFields: memberCount > 0
        ? [{ key: "members", label: "COUNTING DOWN", value: memberCount === 1 ? "1 person" : `${memberCount} people` }]
        : [],
      backFields,
    },
  };
}

/** Wallet's manifest: a SHA-1 of every file in the pass. */
export function manifest(files: Record<string, Uint8Array>): Record<string, string> {
  return Object.fromEntries(Object.entries(files).map(([name, data]) => [name, createHash("sha1").update(data).digest("hex")]));
}

/** A detached PKCS #7 signature of the manifest, with the WWDR certificate included. */
export function signManifest(manifestJSON: Uint8Array, env: WalletEnv = process.env): Uint8Array {
  const fix = (pem?: string) => (pem ?? "").replace(/\\n/g, "\n");
  const certificate = forge.pki.certificateFromPem(fix(env.PASS_CERT_PEM));
  const wwdr = forge.pki.certificateFromPem(fix(env.PASS_WWDR_PEM));
  const keyPem = fix(env.PASS_KEY_PEM);
  const key = env.PASS_KEY_PASSPHRASE
    ? forge.pki.decryptRsaPrivateKey(keyPem, env.PASS_KEY_PASSPHRASE)
    : forge.pki.privateKeyFromPem(keyPem);
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(Buffer.from(manifestJSON).toString("binary"));
  p7.addCertificate(certificate);
  p7.addCertificate(wwdr);
  p7.addSigner({
    key,
    certificate,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() as unknown as string },
    ],
  });
  p7.sign({ detached: true });
  return Buffer.from(forge.asn1.toDer(p7.toAsn1()).getBytes(), "binary");
}

/** Zips pass.json, the images, the manifest and its signature into a .pkpass. */
export function buildPkpass(pass: object, images: Record<string, Uint8Array>, env: WalletEnv = process.env): Uint8Array {
  const files: Record<string, Uint8Array> = { "pass.json": Buffer.from(JSON.stringify(pass)), ...images };
  const manifestJSON = Buffer.from(JSON.stringify(manifest(files)));
  return zipSync({ ...files, "manifest.json": manifestJSON, signature: signManifest(manifestJSON, env) });
}
