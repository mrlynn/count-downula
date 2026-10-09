import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import { after } from "next/server";
import { getCountdown, recordEmbedView, toPublic } from "@/lib/countdowns.ts";
import { embeddable, embedOptions } from "@/lib/embed.ts";
import { logEvent, referrerSource } from "@/lib/events.ts";
import { publicOrigin, shareURL } from "@/lib/http.ts";
import { loadRecap, recapText } from "@/lib/recap.ts";
import { isSlug } from "@/lib/validate.ts";
import { EmbedCountdown } from "./EmbedCountdown.tsx";

export const dynamic = "force-dynamic";

// A frame whose color scheme differs from the page around it is painted opaque, which would put
// dark corners on a light site. Matching the host's default keeps the rounded card see-through.
export const viewport: Viewport = { colorScheme: "normal" };

type Props = { params: Promise<{ slug: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  return {
    title: "Count Downcula",
    // The live page is the one search engines should know.
    robots: { index: false, follow: true },
    alternates: isSlug(slug) ? { canonical: shareURL(slug) } : undefined,
  };
}

/** A small live countdown for an iframe on someone else's site. */
export default async function EmbedPage({ params, searchParams }: Props) {
  const { slug } = await params;
  const doc = isSlug(slug) ? await getCountdown(slug) : null;
  if (!doc) notFound();
  const options = embedOptions(await searchParams);
  const h = await headers();
  // The site it's on: the iframe's referrer is the embedding page (just its origin, by policy).
  const site = referrerSource(h.get("referer"), new URL(publicOrigin()).hostname);
  if (embeddable(doc)) {
    after(() => recordEmbedView(slug).catch(() => {}));
    after(() => logEvent("embed_view", { headers: h }, { slug, source: site }));
  }
  const recap = await loadRecap(doc);
  const words = recap ? recapText(recap, doc.visibility === "public") : null;
  return (
    <>
      {/* The host page shows through around the card. */}
      <style>{`
        html, body { background: transparent !important; color-scheme: normal !important; }
        /* Short frames drop the title so the numbers keep their room. */
        @media (max-height: 150px) { .embed-title { display: none; } }
        @media (max-height: 110px) { .embed-credit { display: none; } }
      `}</style>
      {embeddable(doc) ? (
        <EmbedCountdown
          countdown={toPublic(doc)}
          photoURL={doc.hasPhoto ? `/c/${slug}/photo?v=${doc.updatedAt.getTime()}` : null}
          serverNow={Date.now()}
          options={options}
          recapLine={words ? (words.together ?? words.counted) : null}
          liveURL={`${shareURL(slug)}?src=embed`}
        />
      ) : (
        <p style={{ fontFamily: "system-ui, sans-serif", color: "#888", padding: 16 }}>This countdown can't be embedded.</p>
      )}
    </>
  );
}
