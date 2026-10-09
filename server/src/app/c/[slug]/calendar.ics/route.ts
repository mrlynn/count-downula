import { after } from "next/server";
import { icsFor } from "@/lib/calendar.ts";
import { getCountdown } from "@/lib/countdowns.ts";
import { noteCalendarClient } from "@/lib/calendarClients.ts";
import { shareURL } from "@/lib/http.ts";
import { isSlug } from "@/lib/validate.ts";

/** The countdown as a calendar feed. Calendar apps poll it, so owner edits reach subscribers. */
export async function GET(request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const doc = isSlug(slug) ? await getCountdown(slug) : null;
  if (!doc) return new Response("Not found", { status: 404 });
  after(() => noteCalendarClient(slug, request).catch(() => {}));
  return new Response(icsFor(doc, `${shareURL(slug)}?src=calendar`), {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": `inline; filename="${slug}.ics"`,
      "Cache-Control": "public, max-age=300, s-maxage=900, stale-while-revalidate=900",
      "X-Robots-Tag": "noindex",
    },
  });
}
