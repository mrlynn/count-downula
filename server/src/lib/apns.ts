// Silent pushes to members' devices when a shared countdown changes, through Apple Push
// Notification service. Needs APNS_KEY_ID, APNS_TEAM_ID and APNS_PRIVATE_KEY (the .p8 contents);
// without them pushes are skipped and members catch up on their next refresh.
import { sign } from "node:crypto";
import { connect } from "node:http2";

export interface PushTarget {
  token: string;
  /** Debug builds register with Apple's sandbox; TestFlight and App Store builds with production. */
  sandbox: boolean;
}

export type PushOutcome = "sent" | "gone" | "failed";

export interface ApnsResponse {
  status: number;
  reason?: string;
}

/** One request to APNs. Swappable so tests don't talk to Apple. */
export type Transport = (host: string, path: string, headers: Record<string, string>, body: string) => Promise<ApnsResponse>;

export const TOPIC = "com.countdownula.app";

/** Just the variables this file reads, so tests can pass a plain object. */
export type ApnsEnv = Record<string, string | undefined>;

export function apnsConfigured(env: ApnsEnv = process.env): boolean {
  return Boolean(env.APNS_KEY_ID && env.APNS_TEAM_ID && env.APNS_PRIVATE_KEY);
}

let cached: { jwt: string; issuedAt: number; keyId: string } | undefined;

/** The provider token APNs wants: an ES256 JWT, reused for up to 50 minutes (Apple allows 60). */
export function providerToken(env: ApnsEnv = process.env, now = Date.now()): string {
  const keyId = env.APNS_KEY_ID ?? "";
  const issuedAt = Math.floor(now / 1000);
  if (cached && cached.keyId === keyId && issuedAt - cached.issuedAt < 50 * 60) return cached.jwt;
  const encode = (value: object) => Buffer.from(JSON.stringify(value)).toString("base64url");
  const unsigned = `${encode({ alg: "ES256", kid: keyId })}.${encode({ iss: env.APNS_TEAM_ID, iat: issuedAt })}`;
  // Vercel env vars often carry the .p8 with literal \n; turn those back into newlines.
  const key = (env.APNS_PRIVATE_KEY ?? "").replace(/\\n/g, "\n");
  const signature = sign("sha256", Buffer.from(unsigned), { key, dsaEncoding: "ieee-p1363" }).toString("base64url");
  cached = { jwt: `${unsigned}.${signature}`, issuedAt, keyId };
  return cached.jwt;
}

export const http2Transport: Transport = (host, path, headers, body) =>
  new Promise((resolve) => {
    const session = connect(`https://${host}`);
    session.on("error", () => resolve({ status: 0, reason: "ConnectionError" }));
    const request = session.request({ ":method": "POST", ":path": path, ...headers });
    let status = 0;
    let data = "";
    request.on("response", (h) => (status = Number(h[":status"])));
    request.on("data", (chunk) => (data += chunk));
    request.on("end", () => {
      session.close();
      let reason: string | undefined;
      try {
        reason = data ? (JSON.parse(data) as { reason?: string }).reason : undefined;
      } catch {}
      resolve({ status, reason });
    });
    request.on("error", () => {
      session.close();
      resolve({ status: 0, reason: "RequestError" });
    });
    request.end(body);
  });

export interface LivePush {
  token: string;
  sandbox: boolean;
  /** The APNs payload: an ActivityKit start, update or end event. */
  payload: object;
}

/**
 * Starts, updates or ends Live Activities through APNs (push type liveactivity). Returns each
 * token's outcome, like `sendBackgroundPush`.
 */
export async function sendLiveActivityPushes(
  pushes: LivePush[],
  { env = process.env, transport = http2Transport }: { env?: ApnsEnv; transport?: Transport } = {},
): Promise<Map<string, PushOutcome>> {
  const outcomes = new Map<string, PushOutcome>();
  if (!apnsConfigured(env) || pushes.length === 0) return outcomes;
  const headers = {
    authorization: `bearer ${providerToken(env)}`,
    "apns-topic": `${TOPIC}.push-type.liveactivity`,
    "apns-push-type": "liveactivity",
    "apns-priority": "10",
  };
  await Promise.all(
    pushes.map(async ({ token, sandbox, payload }) => {
      const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const { status, reason } = await transport(host, `/3/device/${token}`, headers, JSON.stringify(payload));
      const gone = status === 410 || (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"));
      outcomes.set(token, status === 200 ? "sent" : gone ? "gone" : "failed");
    }),
  );
  return outcomes;
}

/**
 * Wakes members' apps in the background so they fetch the owner's latest copy. Returns each
 * token's outcome; "gone" tokens belong to uninstalled apps and should be forgotten.
 */
export async function sendBackgroundPush(
  targets: PushTarget[],
  slug: string,
  { env = process.env, transport = http2Transport }: { env?: ApnsEnv; transport?: Transport } = {},
): Promise<Map<string, PushOutcome>> {
  const outcomes = new Map<string, PushOutcome>();
  if (!apnsConfigured(env) || targets.length === 0) return outcomes;
  const body = JSON.stringify({ aps: { "content-available": 1 }, countdownula: { slug } });
  const headers = {
    authorization: `bearer ${providerToken(env)}`,
    "apns-topic": TOPIC,
    "apns-push-type": "background",
    // Background pushes must go at low priority.
    "apns-priority": "5",
    // Only the latest change matters; a delayed push for an old one is useless.
    "apns-collapse-id": slug,
  };
  await Promise.all(
    targets.map(async ({ token, sandbox }) => {
      const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const { status, reason } = await transport(host, `/3/device/${token}`, headers, body);
      const gone = status === 410 || (status === 400 && (reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic"));
      outcomes.set(token, status === 200 ? "sent" : gone ? "gone" : "failed");
    }),
  );
  return outcomes;
}
