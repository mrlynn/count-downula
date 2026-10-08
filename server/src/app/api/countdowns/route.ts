import { NextResponse } from "next/server";
import { createCountdown, toPublic } from "@/lib/countdowns.ts";
import { errorResponse, readJSON, shareURL, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { poolFlag, validateCountdown, validatePhoto } from "@/lib/validate.ts";

/** Publish a countdown. Returns its link and the owner token the app keeps in the Keychain. */
export async function POST(request: Request) {
  const client = clientSubject(request);
  const verdict = await checkLimits([
    [limits.publishPerHour, client],
    [limits.publishPerDay, client],
    [limits.publishAllPerHour, "all"],
  ]);
  if (!verdict.ok) return tooManyRequests(verdict, "new links");

  let body: Record<string, unknown>;
  try {
    body = (await readJSON(request)) as Record<string, unknown>;
  } catch {
    return errorResponse(400, "Send a JSON body under 1 MB.");
  }
  const countdown = validateCountdown(body?.countdown);
  if (!countdown.ok) return errorResponse(422, countdown.error);
  const photo = validatePhoto(body?.photo);
  if (!photo.ok) return errorResponse(422, photo.error);

  const { doc, ownerToken } = await createCountdown(countdown.value, photo.value ?? undefined, poolFlag(body?.countdown) === true);
  return NextResponse.json(
    { slug: doc.slug, url: shareURL(doc.slug), ownerToken, countdown: toPublic(doc) },
    { status: 201 },
  );
}
