// Synchronized zero: every phone in a shared countdown gets its Live Activity eight hours before
// zero (push-to-start, iOS 17.2 and later) and a celebration at zero, even if the app never opened.
// Planning is pure so it's easy to test; /api/cron/live sends what this plans, once a minute.
import type { Collection } from "mongodb";
import type { CountdownDoc } from "./countdowns.ts";
import { db } from "./mongo.ts";

/** How long before zero the Live Activity starts. iOS keeps one running for at most eight hours. */
export const START_WINDOW_MS = 8 * 3_600_000;
/** After zero, how long a missed celebration is still worth sending. */
export const END_GRACE_MS = 2 * 3_600_000;
/** How long the celebration stays on the Lock Screen. */
export const DISMISS_AFTER_MS = 4 * 3_600_000;

/** A phone in a shared countdown, as it registered itself. */
export interface LiveDevice {
  slug: string;
  deviceID: string;
  /** The phone's own local ID for the countdown, which its Live Activity is keyed by. */
  countdownID: string;
  /** Push-to-start token (iOS 17.2+); absent on older phones. */
  startToken?: string;
  /** Tokens of Live Activities running for this countdown on this phone. */
  activityTokens: string[];
  sandbox: boolean;
  /** The target date this phone was last sent a start for, so each phone gets one per date. */
  startedFor?: Date;
}

export type LiveCountdown = Pick<CountdownDoc, "slug" | "title" | "kind" | "targetDate" | "createdAt" | "style"> & {
  liveEndedFor?: Date;
};

export interface PlannedPush {
  token: string;
  sandbox: boolean;
  phase: "start" | "end";
  payload: object;
  deviceID: string;
}

/** ActivityKit decodes dates the Swift default way: seconds since January 1, 2001. */
export const referenceSeconds = (date: Date) => (date.getTime() - Date.UTC(2001, 0, 1)) / 1000;
const unixSeconds = (date: Date) => Math.floor(date.getTime() / 1000);

/** CountdownActivityAttributes.ContentState, as the app encodes it. */
export function contentState(countdown: LiveCountdown, celebrating: boolean) {
  return {
    title: countdown.title,
    startDate: referenceSeconds(countdown.createdAt),
    targetDate: referenceSeconds(countdown.targetDate),
    celebrating,
  };
}

export function startPayload(countdown: LiveCountdown, device: LiveDevice, now: Date) {
  const accent = (countdown.style as { accent?: unknown }).accent;
  return {
    aps: {
      timestamp: unixSeconds(now),
      event: "start",
      "content-state": contentState(countdown, false),
      "attributes-type": "CountdownActivityAttributes",
      attributes: { countdownID: device.countdownID, kind: countdown.kind, ...(accent ? { accent } : {}) },
      "stale-date": unixSeconds(countdown.targetDate),
      alert: { title: countdown.title, body: "Counting down together. It's on your Lock Screen until zero." },
    },
  };
}

export function endPayload(countdown: LiveCountdown, now: Date) {
  return {
    aps: {
      timestamp: unixSeconds(now),
      event: "end",
      "content-state": contentState(countdown, true),
      "dismissal-date": unixSeconds(new Date(countdown.targetDate.getTime() + DISMISS_AFTER_MS)),
      alert: { title: `🎉 ${countdown.title}`, body: "It's here!", sound: "default" },
    },
  };
}

/**
 * What to send for one countdown right now. Inside the eight hour window, each phone gets one start
 * per target date (so people who join late still get it); the celebration goes out once at zero, or
 * soon after if a run was missed. An edit that moves the date makes both eligible again.
 */
export function planPushes(countdown: LiveCountdown, devices: LiveDevice[], now: Date): PlannedPush[] {
  const target = countdown.targetDate.getTime();
  const t = now.getTime();
  if (countdown.kind === "countUp") return [];
  const sameTarget = (d?: Date) => d?.getTime() === target;

  if (target > t && target - t <= START_WINDOW_MS) {
    return devices
      .filter((d) => d.startToken && !sameTarget(d.startedFor))
      .map((d) => ({
        token: d.startToken!, sandbox: d.sandbox, phase: "start" as const,
        payload: startPayload(countdown, d, now), deviceID: d.deviceID,
      }));
  }
  if (target <= t && t - target < END_GRACE_MS && !sameTarget(countdown.liveEndedFor)) {
    const payload = endPayload(countdown, now);
    return devices.flatMap((d) =>
      [...new Set(d.activityTokens)].map((token) => ({ token, sandbox: d.sandbox, phase: "end" as const, payload, deviceID: d.deviceID })),
    );
  }
  return [];
}

// MARK: - Storage

interface LiveDeviceDoc extends LiveDevice {
  /** Hash of the owner or member key that registered it, so leaving removes the device too. */
  authorHash: string;
  updatedAt: Date;
}

let indexesReady: Promise<unknown> | undefined;

async function devicesCollection(): Promise<Collection<LiveDeviceDoc>> {
  const collection = (await db()).collection<LiveDeviceDoc>("liveDevices");
  indexesReady ??= collection.createIndex({ slug: 1, deviceID: 1 }, { unique: true });
  await indexesReady;
  return collection;
}

export interface LiveRegistration {
  deviceID: string;
  countdownID: string;
  startToken?: string;
  activityToken?: string;
  sandbox: boolean;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const HEX = /^[0-9a-f]{64,512}$/i;

/** Checks a registration body. Pure, for tests. */
export function validateRegistration(body: unknown): { ok: true; value: LiveRegistration } | { ok: false; error: string } {
  const b = (body ?? {}) as Record<string, unknown>;
  if (typeof b.deviceID !== "string" || !UUID.test(b.deviceID)) return { ok: false, error: "deviceID must be a UUID." };
  if (typeof b.countdownID !== "string" || !UUID.test(b.countdownID)) return { ok: false, error: "countdownID must be a UUID." };
  for (const key of ["startToken", "activityToken"] as const) {
    if (b[key] !== undefined && (typeof b[key] !== "string" || !HEX.test(b[key] as string))) {
      return { ok: false, error: `${key} must be a hex token.` };
    }
  }
  return {
    ok: true,
    value: {
      deviceID: b.deviceID.toLowerCase(), countdownID: b.countdownID.toUpperCase(),
      startToken: (b.startToken as string | undefined)?.toLowerCase(),
      activityToken: (b.activityToken as string | undefined)?.toLowerCase(),
      sandbox: b.sandbox === true,
    },
  };
}

export async function registerLiveDevice(slug: string, authorHash: string, r: LiveRegistration) {
  await (await devicesCollection()).updateOne(
    { slug, deviceID: r.deviceID },
    {
      $set: {
        authorHash, countdownID: r.countdownID, sandbox: r.sandbox, updatedAt: new Date(),
        ...(r.startToken ? { startToken: r.startToken } : {}),
      },
      // Keep the last few; a phone only runs one activity per countdown at a time.
      ...(r.activityToken ? { $push: { activityTokens: { $each: [r.activityToken], $slice: -5 } } } : {}),
      $setOnInsert: r.activityToken ? {} : { activityTokens: [] },
    },
    { upsert: true },
  );
}

export async function liveDevicesFor(slug: string): Promise<LiveDevice[]> {
  return (await devicesCollection()).find({ slug }).toArray();
}

/** Someone left: their phones stop getting this countdown's Live Activity. */
export async function forgetLiveDevices(slug: string, authorHash?: string) {
  await (await devicesCollection()).deleteMany(authorHash ? { slug, authorHash } : { slug });
}

/** Drops tokens APNs says are dead. */
export async function forgetLiveTokens(tokens: string[]) {
  if (tokens.length === 0) return;
  const collection = await devicesCollection();
  await collection.updateMany({ startToken: { $in: tokens } }, { $unset: { startToken: "" } });
  await collection.updateMany({ activityTokens: { $in: tokens } }, { $pull: { activityTokens: { $in: tokens } } });
}

/** Records which phones were sent a start for this target date. */
export async function markStarted(slug: string, deviceIDs: string[], target: Date) {
  if (deviceIDs.length === 0) return;
  await (await devicesCollection()).updateMany({ slug, deviceID: { $in: deviceIDs } }, { $set: { startedFor: target } });
}

/** Lets phones whose start failed get another try. */
export async function unmarkStarted(slug: string, deviceIDs: string[]) {
  if (deviceIDs.length === 0) return;
  await (await devicesCollection()).updateMany({ slug, deviceID: { $in: deviceIDs } }, { $unset: { startedFor: "" } });
}

/** Once a celebration is sent, those activities are over. */
export async function clearActivityTokens(slug: string) {
  await (await devicesCollection()).updateMany({ slug }, { $set: { activityTokens: [] } });
}
