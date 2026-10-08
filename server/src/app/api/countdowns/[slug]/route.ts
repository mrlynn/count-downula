import { NextResponse } from "next/server";
import { deleteCountdown, getCountdown, toPublic, updateCountdown } from "@/lib/countdowns.ts";
import { bearer, errorResponse, readJSON, shareURL, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { isSlug, validateCountdown, validatePhoto } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

export async function GET(_request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const doc = await getCountdown(slug);
  if (!doc) return errorResponse(404, "Not found.");
  return NextResponse.json(
    { url: shareURL(slug), countdown: toPublic(doc) },
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

  const { result, doc } = await updateCountdown(slug, bearer(request), countdown.value, photo.value);
  if (result === "not-found") return errorResponse(404, "Not found.");
  if (result === "forbidden") return errorResponse(403, "That owner token doesn't match this countdown.");
  return NextResponse.json({ slug, url: shareURL(slug), countdown: doc ? toPublic(doc) : null });
}

export async function DELETE(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const verdict = await checkLimits([[limits.deletesPerHour, clientSubject(request)]]);
  if (!verdict.ok) return tooManyRequests(verdict, "deleted links");
  const result = await deleteCountdown(slug, bearer(request));
  if (result === "not-found") return errorResponse(404, "Not found.");
  if (result === "forbidden") return errorResponse(403, "That owner token doesn't match this countdown.");
  return new NextResponse(null, { status: 204 });
}
