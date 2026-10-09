import { after, NextResponse } from "next/server";
import { getCountdown, hashToken } from "@/lib/countdowns.ts";
import { logEvent } from "@/lib/events.ts";
import { applyHostPass } from "@/lib/host.ts";
import { bearer, errorResponse, readJSON, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { verifyTransaction } from "@/lib/storekit.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

/**
 * Applies a Host Pass bought in the app. Body `{ transaction }`: StoreKit 2's signed transaction
 * (its jwsRepresentation), checked here against Apple's certificate chain. Owner only.
 */
export async function POST(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const verdict = await checkLimits([[limits.editsPerHour, clientSubject(request)]]);
  if (!verdict.ok) return tooManyRequests(verdict, "requests");
  const doc = await getCountdown(slug);
  if (!doc) return errorResponse(404, "Not found.");
  const token = bearer(request);
  if (!token || hashToken(token) !== doc.ownerTokenHash) return errorResponse(403, "Only the countdown's owner can host it.");
  let body: { transaction?: unknown };
  try {
    body = (await readJSON(request)) as typeof body;
  } catch {
    return errorResponse(400, "Send a JSON body.");
  }
  const verified = verifyTransaction(String(body?.transaction ?? ""), { allowXcode: process.env.HOST_PASS_ALLOW_XCODE === "true" });
  if (!verified.ok) return errorResponse(422, verified.error);
  const result = await applyHostPass(slug, verified.value);
  if (result === "used-elsewhere") return errorResponse(409, "That Host Pass is already hosting another countdown.");
  if (result === "applied") after(() => logEvent("host_pass_applied", request, { slug, source: verified.value.environment.toLowerCase() }));
  return NextResponse.json({ host: true });
}
