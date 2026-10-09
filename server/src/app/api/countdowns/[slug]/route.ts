import { after, NextResponse } from "next/server";
import { deleteCountdown, getCountdown, memberCount, pushTargets, toPublic, updateCountdown } from "@/lib/countdowns.ts";
import { logEvent } from "@/lib/events.ts";
import { loadRecap } from "@/lib/recap.ts";
import { notifyMembers } from "@/lib/notify.ts";
import { purgeCoffin } from "@/lib/coffin.ts";
import { purgePool } from "@/lib/pool.ts";
import { forgetLiveDevices } from "@/lib/live.ts";
import { forgetPass, pushPassUpdates } from "@/lib/walletPass.ts";
import { bearer, errorResponse, readJSON, shareURL, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { isSlug, poolFlag, validateCountdown, validatePhoto } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

export async function GET(_request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const doc = await getCountdown(slug);
  if (!doc) return errorResponse(404, "Not found.");
  const [members, recap] = await Promise.all([memberCount(slug), loadRecap(doc)]);
  return NextResponse.json(
    { url: shareURL(slug), countdown: toPublic(doc), memberCount: members, ...(recap ? { recap } : {}) },
    { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300" } },
  );
}

/** Owner edits. `photo` left out keeps the current one, null removes it. */
export async function PUT(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const verdict = await checkLimits([
    [limits.editsPerHour, clientSubject(request)],
    [limits.editsPerCountdownPerHour, slug],
  ]);
  if (!verdict.ok) return tooManyRequests(verdict, "updates to this link");
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

  const { result, doc } = await updateCountdown(slug, bearer(request), countdown.value, photo.value, poolFlag(body?.countdown));
  if (result === "not-found") return errorResponse(404, "Not found.");
  if (result === "forbidden") return errorResponse(403, "That owner token doesn't match this countdown.");
  // Members' apps fetch the new copy as soon as they're woken.
  after(() => notifyMembers(slug).catch(() => {}));
  // Wallet passes of this countdown fetch the new version.
  after(() => pushPassUpdates(slug).catch(() => {}));
  return NextResponse.json({ slug, url: shareURL(slug), countdown: doc ? toPublic(doc) : null });
}

export async function DELETE(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const verdict = await checkLimits([[limits.deletesPerHour, clientSubject(request)]]);
  if (!verdict.ok) return tooManyRequests(verdict, "deleted links");
  // Collected first: unpublishing deletes the member list, but members should still hear about it.
  const targets = await pushTargets(slug);
  const result = await deleteCountdown(slug, bearer(request));
  if (result === "not-found") return errorResponse(404, "Not found.");
  if (result === "forbidden") return errorResponse(403, "That owner token doesn't match this countdown.");
  after(() => notifyMembers(slug, targets).catch(() => {}));
  // Sealed notes and photos go with it.
  after(() => purgeCoffin(slug).catch(() => {}));
  after(() => purgePool(slug).catch(() => {}));
  after(() => forgetLiveDevices(slug).catch(() => {}));
  after(() => logEvent("unpublish", request, { slug }));
  after(() => forgetPass(slug).catch(() => {}));
  return new NextResponse(null, { status: 204 });
}
