import { NextResponse } from "next/server";
import { upsertCrypt } from "@/lib/crypt.ts";
import { upcomingHolidays } from "@/lib/holidays.ts";

/**
 * Runs daily (server/vercel.json). Keeps the next occurrence of every yearly holiday and fun day in
 * the Crypt, so each one comes back the day after it drops off. Creating an entry that already
 * exists only refreshes it, so running it again changes nothing.
 */
export async function GET(request: Request) {
  // Vercel sends the project's CRON_SECRET; anything else is turned away.
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return new NextResponse("Unauthorized", { status: 401 });
  }
  const entries = upcomingHolidays(new Date());
  await upsertCrypt(entries);
  return NextResponse.json({ upserted: entries.map((e) => e.slug) });
}
