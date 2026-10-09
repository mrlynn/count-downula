import { get } from "@vercel/blob";
import { contributions, photoPathsOf, parseId, reportSignatureValid } from "@/lib/coffin.ts";

type Context = { params: Promise<{ id: string }> };

/** The reported photo, for the review page only. */
export async function GET(request: Request, { params }: Context) {
  const { id } = await params;
  const _id = parseId(id);
  const sig = new URL(request.url).searchParams.get("sig") ?? "";
  if (!_id || !reportSignatureValid(id, sig)) return new Response("Not found.", { status: 404 });
  const contribution = await (await contributions()).findOne({ _id });
  const first = contribution ? photoPathsOf(contribution)[0] : undefined;
  if (!first) return new Response("Not found.", { status: 404 });
  const blob = await get(first, { access: "private" });
  if (!blob || blob.statusCode !== 200) return new Response("Not found.", { status: 404 });
  return new Response(blob.stream, { headers: { "Content-Type": "image/jpeg", "Cache-Control": "no-store" } });
}
