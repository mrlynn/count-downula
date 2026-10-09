import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import { after } from "next/server";
import { getCountdown, toPublic } from "@/lib/countdowns.ts";
import { logEvent } from "@/lib/events.ts";
import { linkFor } from "@/lib/http.ts";
import { pickLocale } from "@/lib/i18n.ts";
import { qrPath, roomLink } from "@/lib/present.ts";
import { isSlug } from "@/lib/validate.ts";
import { Present } from "./Present.tsx";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const doc = isSlug(slug) ? await getCountdown(slug) : null;
  // The room's screen isn't something to find in search; the live page is.
  return { title: doc ? `${doc.title} · Count Downcula` : "Count Downcula", robots: { index: false } };
}

/** The countdown full screen, for a TV, a projector or a laptop. */
export default async function PresentPage({ params }: Props) {
  const { slug } = await params;
  const doc = isSlug(slug) ? await getCountdown(slug) : null;
  if (!doc) notFound();
  const h = await headers();
  after(() => logEvent("present_view", { headers: h }, { slug, source: "web" }));
  const room = roomLink(linkFor(doc));
  return (
    <Present
      countdown={toPublic(doc)}
      photoURL={doc.hasPhoto ? `/c/${slug}/photo?v=${doc.updatedAt.getTime()}` : null}
      serverNow={Date.now()}
      qr={qrPath(room)}
      locale={pickLocale(h.get("accept-language"))}
    />
  );
}
