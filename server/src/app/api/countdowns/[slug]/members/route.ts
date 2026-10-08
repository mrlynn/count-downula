import { NextResponse } from "next/server";
import { joinCountdown, leaveCountdown } from "@/lib/countdowns.ts";
import { bearer, errorResponse, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

/** Join a shared countdown. Returns a member key the app keeps in the Keychain, used only to leave. */
export async function POST(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const verdict = await checkLimits([
    [limits.joinsPerHour, clientSubject(request)],
    [limits.joinsPerCountdownPerHour, slug],
  ]);
  if (!verdict.ok) return tooManyRequests(verdict, "joins");
  const joined = await joinCountdown(slug);
  if (!joined) return errorResponse(404, "This countdown isn't shared anymore.");
  return NextResponse.json(joined, { status: 201 });
}

/** Leave. Always succeeds, so a device can retry without checking first. */
export async function DELETE(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  await leaveCountdown(slug, bearer(request));
  return new NextResponse(null, { status: 204 });
}
