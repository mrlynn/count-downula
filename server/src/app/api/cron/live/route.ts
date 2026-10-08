import { NextResponse } from "next/server";
import { apnsConfigured, sendLiveActivityPushes } from "@/lib/apns.ts";
import { db } from "@/lib/mongo.ts";
import {
  clearActivityTokens, END_GRACE_MS, forgetLiveTokens, liveDevicesFor, markStarted, planPushes, START_WINDOW_MS,
  unmarkStarted,
  type LiveCountdown,
} from "@/lib/live.ts";

/**
 * Runs every minute (server/vercel.json). Starts Live Activities eight hours before zero and sends
 * the celebration at zero, for every shared countdown with registered phones.
 */
export async function GET(request: Request) {
  // Vercel sends the project's CRON_SECRET; anything else is turned away.
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new NextResponse("Unauthorized", { status: 401 });
  }
  // Without an APNs key nothing can be sent, so don't mark anything as started either.
  if (!apnsConfigured()) return NextResponse.json({ skipped: "APNs key not configured" });
  const now = new Date();
  const countdowns = (await db()).collection<LiveCountdown>("countdowns");
  const due = await countdowns
    .find({
      kind: { $ne: "countUp" },
      floating: { $exists: false },
      targetDate: { $gt: new Date(now.getTime() - END_GRACE_MS), $lte: new Date(now.getTime() + START_WINDOW_MS) },
    })
    .project<LiveCountdown>({ slug: 1, title: 1, kind: 1, targetDate: 1, createdAt: 1, style: 1, liveEndedFor: 1 })
    .toArray();

  let sent = 0;
  for (const countdown of due) {
    const plan = planPushes(countdown, await liveDevicesFor(countdown.slug), now);
    if (plan.length === 0) continue;
    if (countdown.targetDate > now) {
      // Starts: mark each phone first, so an overlapping run doesn't send it twice.
      await markStarted(countdown.slug, plan.map((p) => p.deviceID), countdown.targetDate);
    } else {
      // The celebration: claim it once per target date.
      const claimed = await countdowns.updateOne(
        { slug: countdown.slug, liveEndedFor: { $ne: countdown.targetDate } },
        { $set: { liveEndedFor: countdown.targetDate } },
      );
      if (claimed.modifiedCount === 0) continue;
    }
    const outcomes = await sendLiveActivityPushes(plan);
    const delivered = [...outcomes.values()].filter((o) => o === "sent").length;
    sent += delivered;
    await forgetLiveTokens([...outcomes].filter(([, o]) => o === "gone").map(([token]) => token));
    // Failures (Apple unreachable, a bad key) get another try next minute.
    const failed = plan.filter((p) => outcomes.get(p.token) === "failed");
    if (countdown.targetDate > now) {
      await unmarkStarted(countdown.slug, failed.map((p) => p.deviceID));
    } else if (delivered === 0 && failed.length > 0) {
      await countdowns.updateOne({ slug: countdown.slug }, { $unset: { liveEndedFor: "" } });
    } else {
      await clearActivityTokens(countdown.slug);
    }
  }
  return NextResponse.json({ checked: due.length, sent });
}
