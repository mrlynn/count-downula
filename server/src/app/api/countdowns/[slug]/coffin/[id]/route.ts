import { del } from "@vercel/blob";
import { NextResponse } from "next/server";
import { contributions, loadCountdownAndRole, parseId } from "@/lib/coffin.ts";
import { hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse } from "@/lib/http.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string; id: string }> };

/** Take a contribution out: its author, or the owner (who can remove anything). */
export async function DELETE(request: Request, { params }: Context) {
  const { slug, id } = await params;
  const _id = parseId(id);
  if (!isSlug(slug) || !_id) return errorResponse(404, "Not found.");
  const token = bearer(request);
  const { doc, role } = await loadCountdownAndRole(slug, token);
  if (!doc || !role) return errorResponse(404, "Not found.");
  const collection = await contributions();
  const contribution = await collection.findOne({ _id, slug, removedAt: { $exists: false } });
  if (!contribution) return new NextResponse(null, { status: 204 });
  if (role !== "owner" && contribution.authorTokenHash !== hashToken(token!)) {
    return errorResponse(403, "Only its author or the countdown's owner can remove this.");
  }
  await collection.updateOne({ _id }, { $set: { removedAt: new Date() }, $unset: { photoPath: "" } });
  if (contribution.photoPath) await del(contribution.photoPath).catch(() => {});
  return new NextResponse(null, { status: 204 });
}
