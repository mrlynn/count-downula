import { NextResponse } from "next/server";
import { getCountdown, isOwner } from "@/lib/countdowns.ts";
import { editLinksEnabled, sendEditLinkEmail } from "@/lib/email.ts";
import { bearer, errorResponse, publicOrigin, readJSON, tooManyRequests } from "@/lib/http.ts";
import { pickLocale, t } from "@/lib/i18n.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { isSlug } from "@/lib/validate.ts";
import { editLink, looksLikeEmail } from "@/lib/webCreate.ts";

/**
 * Emails the owner of a web-made countdown a link that edits it from any browser. Only the owner
 * token can ask, and the address is used once to send and never stored.
 */
export async function POST(request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  if (!editLinksEnabled()) return errorResponse(503, "Edit links can't be emailed right now.");
  const token = bearer(request);
  const owner = await isOwner(slug, token);
  if (owner === "not-found") return errorResponse(404, "Not found.");
  if (owner === "forbidden" || !token) return errorResponse(403, "That owner token doesn't match this countdown.");
  const verdict = await checkLimits([
    [limits.editLinksPerHour, clientSubject(request)],
    [limits.editLinksPerCountdownPerDay, slug],
  ]);
  if (!verdict.ok) return tooManyRequests(verdict, "edit links");
  let body: { email?: unknown };
  try {
    body = (await readJSON(request)) as { email?: unknown };
  } catch {
    return errorResponse(400, "Send a JSON body.");
  }
  const email = typeof body?.email === "string" ? body.email.trim() : "";
  if (!looksLikeEmail(email)) return errorResponse(422, "That doesn't look like an email address.");
  const doc = await getCountdown(slug);
  if (!doc) return errorResponse(404, "Not found.");
  const locale = pickLocale(request.headers.get("accept-language"));
  const sent = await sendEditLinkEmail({
    to: email,
    subject: t(locale, "editEmailSubject", { title: doc.title }),
    lines: [t(locale, "editEmailBody", { title: doc.title }), t(locale, "editEmailKeep")],
    link: editLink(publicOrigin(), slug, token),
    linkLabel: t(locale, "editEmailButton"),
  });
  return sent ? new NextResponse(null, { status: 204 }) : errorResponse(502, "The email didn't go out. Try again.");
}
