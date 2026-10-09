// Builds a countdown's .pkpass, and keeps Wallet's registered devices up to date.
import { connect } from "node:http2";
import type { Collection } from "mongodb";
import { getCountdown, getPhoto, memberCount } from "./countdowns.ts";
import { publicOrigin, shareURL } from "./http.ts";
import { db } from "./mongo.ts";
import { buildPkpass, PASS_TYPE_ID, passJSON } from "./wallet.ts";
import { passImages } from "./walletImages.tsx";

export async function buildPassForSlug(slug: string): Promise<{ bytes: Uint8Array; updatedAt: Date } | null> {
  const doc = await getCountdown(slug);
  if (!doc || doc.kind === "countUp") return null;
  const [photo, members] = await Promise.all([doc.hasPhoto ? getPhoto(slug) : null, memberCount(slug)]);
  const pass = passJSON(doc, { url: `${shareURL(slug)}?src=wallet`, webServiceURL: `${publicOrigin()}/api/wallet`, memberCount: members });
  return { bytes: buildPkpass(pass, await passImages(doc.style, photo)), updatedAt: doc.updatedAt };
}

export function pkpassResponse(bytes: Uint8Array, slug: string, updatedAt: Date): Response {
  return new Response(Buffer.from(bytes), {
    headers: {
      "Content-Type": "application/vnd.apple.pkpass",
      "Content-Disposition": `attachment; filename="${slug}.pkpass"`,
      "Last-Modified": updatedAt.toUTCString(),
      "Cache-Control": "private, no-store",
    },
  });
}

// MARK: - Registrations (Wallet's web service)

interface RegistrationDoc {
  device: string;
  serial: string;
  pushToken: string;
  createdAt: Date;
}

let indexReady: Promise<unknown> | undefined;

async function registrations(): Promise<Collection<RegistrationDoc>> {
  const collection = (await db()).collection<RegistrationDoc>("walletRegistrations");
  indexReady ??= collection.createIndex({ device: 1, serial: 1 }, { unique: true });
  await indexReady;
  return collection;
}

/** True when it's new. */
export async function registerPass(device: string, serial: string, pushToken: string): Promise<boolean> {
  const result = await (await registrations()).updateOne(
    { device, serial },
    { $set: { pushToken }, $setOnInsert: { createdAt: new Date() } },
    { upsert: true },
  );
  return result.upsertedCount > 0;
}

export async function unregisterPass(device: string, serial: string) {
  await (await registrations()).deleteOne({ device, serial });
}

/** Serials registered on a device, optionally only those changed since `since` (a Unix time tag). */
export async function serialsForDevice(device: string, since?: number): Promise<{ serials: string[]; lastUpdated: number }> {
  const serials = (await (await registrations()).find({ device }).toArray()).map((r) => r.serial);
  const countdowns = await (await db()).collection<{ slug: string; updatedAt: Date }>("countdowns")
    .find({ slug: { $in: serials } }, { projection: { slug: 1, updatedAt: 1 } }).toArray();
  const changed = countdowns.filter((c) => since === undefined || Math.floor(c.updatedAt.getTime() / 1000) > since);
  const lastUpdated = Math.max(0, ...countdowns.map((c) => Math.floor(c.updatedAt.getTime() / 1000)));
  return { serials: changed.map((c) => c.slug), lastUpdated };
}

export async function forgetPass(serial: string) {
  await (await registrations()).deleteMany({ serial });
}

/**
 * Tells every device holding this pass to fetch it again. Wallet pushes go to APNs production with
 * the Pass Type ID certificate as the client certificate and an empty payload.
 */
export async function pushPassUpdates(serial: string, env = process.env) {
  if (!env.PASS_CERT_PEM || !env.PASS_KEY_PEM) return;
  const tokens = [...new Set((await (await registrations()).find({ serial }).toArray()).map((r) => r.pushToken))];
  if (tokens.length === 0) return;
  const fix = (pem?: string) => (pem ?? "").replace(/\\n/g, "\n");
  const session = connect("https://api.push.apple.com", {
    cert: fix(env.PASS_CERT_PEM), key: fix(env.PASS_KEY_PEM), passphrase: env.PASS_KEY_PASSPHRASE,
  });
  session.on("error", () => {});
  const gone: string[] = [];
  await Promise.all(
    tokens.map(
      (token) =>
        new Promise<void>((resolve) => {
          const request = session.request({ ":method": "POST", ":path": `/3/device/${token}`, "apns-topic": PASS_TYPE_ID });
          request.on("response", (headers) => {
            if (Number(headers[":status"]) === 410) gone.push(token);
          });
          request.on("close", () => resolve());
          request.on("error", () => resolve());
          request.end("{}");
        }),
    ),
  );
  session.close();
  if (gone.length) await (await registrations()).deleteMany({ pushToken: { $in: gone } });
}
