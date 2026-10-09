import { after, NextResponse } from "next/server";
import { hashToken, joinCountdown, leaveCountdown, setMemberPushToken } from "@/lib/countdowns.ts";
import { logEvent } from "@/lib/events.ts";
import { forgetLiveDevices } from "@/lib/live.ts";
import { bearer, errorResponse, readJSON, tooManyRequests } from "@/lib/http.ts";
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
  after(() => logEvent("join", request, { slug }));
  return NextResponse.json(joined, { status: 201 });
}

/** A member's device registers for a silent push when the owner edits. */
export async function PUT(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  let body: { pushToken?: unknown; sandbox?: unknown };
  try {
    body = (await readJSON(request)) as typeof body;
  } catch {
    return errorResponse(400, "Send a JSON body.");
  }
  const pushToken = typeof body?.pushToken === "string" ? body.pushToken : "";
  if (!/^[0-9a-f]{64,512}$/i.test(pushToken)) return errorResponse(422, "pushToken must be a hex device token.");
  const ok = await setMemberPushToken(slug, bearer(request), pushToken.toLowerCase(), body.sandbox === true);
  if (!ok) return errorResponse(403, "That member key isn't counting down with this countdown.");
  return new NextResponse(null, { status: 204 });
}

/** Leave. Always succeeds, so a device can retry without checking first. */
export async function DELETE(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const token = bearer(request);
  await leaveCountdown(slug, token);
  after(() => logEvent("leave", request, { slug }));
  if (token) await forgetLiveDevices(slug, hashToken(token));
  return new NextResponse(null, { status: 204 });
}
