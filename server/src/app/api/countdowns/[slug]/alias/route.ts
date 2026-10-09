import { NextResponse } from "next/server";
import { getCountdown, hashToken } from "@/lib/countdowns.ts";
import { setAlias, validateAlias } from "@/lib/host.ts";
import { bearer, errorResponse, readJSON, shareURL, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

/** Sets a hosted countdown's custom link, `{ alias: "sarah-and-tom" }`. Owner only. */
export async function PUT(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const verdict = await checkLimits([
    [limits.editsPerHour, clientSubject(request)],
    [limits.editsPerCountdownPerHour, slug],
  ]);
  if (!verdict.ok) return tooManyRequests(verdict, "link changes");
  const doc = await getCountdown(slug);
  if (!doc) return errorResponse(404, "Not found.");
  const token = bearer(request);
  if (!token || hashToken(token) !== doc.ownerTokenHash) return errorResponse(403, "Only the countdown's owner can change its link.");
  if (!doc.host) return errorResponse(402, "Custom links come with a Host Pass.");
  let body: { alias?: unknown };
  try {
    body = (await readJSON(request)) as typeof body;
  } catch {
    return errorResponse(400, "Send a JSON body.");
  }
  const alias = validateAlias(body?.alias);
  if (!alias.ok) return errorResponse(422, alias.error);
  const result = await setAlias(slug, alias.value);
  if (!result.ok) return errorResponse(409, result.error);
  return NextResponse.json({ alias: result.alias, url: shareURL(result.alias) });
}
