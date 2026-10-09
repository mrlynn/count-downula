import { NextResponse } from "next/server";
import { events, validateBatch } from "@/lib/events.ts";
import { errorResponse, readJSON, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";

/** A batch of app-side events (countdown created, paywall shown, daily active). See lib/events.ts. */
export async function POST(request: Request) {
  const verdict = await checkLimits([[limits.eventBatchesPerHour, clientSubject(request)]]);
  if (!verdict.ok) return tooManyRequests(verdict, "event batches");
  let body: unknown;
  try {
    body = await readJSON(request);
  } catch {
    return errorResponse(400, "Send a JSON body under 1 MB.");
  }
  const batch = validateBatch(body);
  if (!batch.ok) return errorResponse(422, batch.error);
  if (batch.docs.length) await (await events()).insertMany(batch.docs, { ordered: false });
  return NextResponse.json({ accepted: batch.docs.length, dropped: batch.dropped }, { status: 202 });
}
