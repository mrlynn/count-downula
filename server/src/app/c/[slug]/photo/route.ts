import { getPhoto } from "@/lib/countdowns.ts";
import { isSlug } from "@/lib/validate.ts";

export async function GET(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const photo = isSlug(slug) ? await getPhoto(slug) : null;
  if (!photo) return new Response("Not found", { status: 404 });
  // The page adds ?v=<updatedAt>, so a new photo always gets a new URL.
  return new Response(new Uint8Array(photo), {
    headers: { "Content-Type": "image/jpeg", "Cache-Control": "public, max-age=86400, s-maxage=86400, immutable" },
  });
}
