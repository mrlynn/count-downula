import { after, NextResponse } from "next/server";
import { contributions, loadCountdownAndRole, parseId, reportSignature } from "@/lib/coffin.ts";
import { sendReportEmail } from "@/lib/email.ts";
import { bearer, errorResponse, publicOrigin, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string; id: string }> };

/** Flag a contribution for review. Anyone in the countdown can; it emails a review link. */
export async function POST(request: Request, { params }: Context) {
  const { slug, id } = await params;
  const _id = parseId(id);
  if (!isSlug(slug) || !_id) return errorResponse(404, "Not found.");
  const { doc, role } = await loadCountdownAndRole(slug, bearer(request));
  if (!doc || !role) return errorResponse(404, "Not found.");
  const verdict = await checkLimits([[limits.reportsPerHour, clientSubject(request)]]);
  if (!verdict.ok) return tooManyRequests(verdict, "reports");
  const contribution = await (await contributions()).findOneAndUpdate(
    { _id, slug, removedAt: { $exists: false } },
    { $inc: { reports: 1 } },
    { returnDocument: "after" },
  );
  if (!contribution) return new NextResponse(null, { status: 204 });
  const reviewURL = `${publicOrigin()}/admin/coffin/${id}?sig=${reportSignature(id)}`;
  after(() =>
    sendReportEmail({
      countdownTitle: doc.title, from: contribution.name, text: contribution.text,
      hasPhoto: Boolean(contribution.photoPath), reports: contribution.reports, reviewURL,
    }).catch(() => false),
  );
  return new NextResponse(null, { status: 204 });
}
