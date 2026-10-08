import { get } from "@vercel/blob";
import { contributions, isOpen, loadCountdownAndRole, parseId } from "@/lib/coffin.ts";
import { hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse } from "@/lib/http.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string; id: string }> };

/** A contribution's photo: for its author any time, for everyone in the countdown after zero. */
export async function GET(request: Request, { params }: Context) {
  const { slug, id } = await params;
  const _id = parseId(id);
  if (!isSlug(slug) || !_id) return errorResponse(404, "Not found.");
  const token = bearer(request);
  const { doc, role } = await loadCountdownAndRole(slug, token);
  if (!doc || !role) return errorResponse(404, "Not found.");
  const contribution = await (await contributions()).findOne({ _id, slug, removedAt: { $exists: false } });
  if (!contribution?.photoPath) return errorResponse(404, "Not found.");
  if (!isOpen(doc) && contribution.authorTokenHash !== hashToken(token!)) return errorResponse(403, "Still sealed.");
  const blob = await get(contribution.photoPath, { access: "private" });
  if (!blob || blob.statusCode !== 200) return errorResponse(404, "Not found.");
  return new Response(blob.stream, { headers: { "Content-Type": "image/jpeg", "Cache-Control": "private, max-age=3600" } });
}
