import { getCountdown, toPublic } from "@/lib/countdowns.ts";
import { logEvent } from "@/lib/events.ts";
import { viewerTarget } from "@/lib/time.ts";
import { isSlug } from "@/lib/validate.ts";

/**
 * A present page that was still open when its countdown hit zero. Sent once per page; only counted
 * near the real zero, so a page left open from last week, or a script, doesn't add to it.
 */
export async function POST(request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const doc = isSlug(slug) ? await getCountdown(slug) : null;
  if (!doc || doc.kind === "countUp") return new Response(null, { status: 204 });
  // A floating time reaches zero at each viewer's midnight, anywhere within a day of it.
  const zero = viewerTarget(toPublic(doc)).getTime();
  const window = doc.floating ? 15 * 3_600_000 : 5 * 60_000;
  if (Math.abs(Date.now() - zero) <= window) await logEvent("present_zero", request, { slug, source: "web" });
  return new Response(null, { status: 204 });
}
