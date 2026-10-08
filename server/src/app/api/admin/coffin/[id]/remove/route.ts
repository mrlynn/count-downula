import { del } from "@vercel/blob";
import { NextResponse } from "next/server";
import { contributions, parseId, reportSignatureValid } from "@/lib/coffin.ts";
import { publicOrigin } from "@/lib/http.ts";

type Context = { params: Promise<{ id: string }> };

/** The review page's Remove button. The signed link from the report email is the authority. */
export async function POST(request: Request, { params }: Context) {
  const { id } = await params;
  const _id = parseId(id);
  const sig = (await request.formData()).get("sig");
  if (!_id || typeof sig !== "string" || !reportSignatureValid(id, sig)) {
    return new NextResponse("That review link isn't valid.", { status: 403 });
  }
  const collection = await contributions();
  const contribution = await collection.findOne({ _id });
  if (contribution && !contribution.removedAt) {
    await collection.updateOne({ _id }, { $set: { removedAt: new Date() }, $unset: { photoPath: "" } });
    if (contribution.photoPath) await del(contribution.photoPath).catch(() => {});
  }
  return NextResponse.redirect(`${publicOrigin()}/admin/coffin/${id}?sig=${encodeURIComponent(sig)}&removed=1`, 303);
}
