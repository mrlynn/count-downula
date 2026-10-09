import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { headers } from "next/headers";
import { after } from "next/server";
import { logEvent, referrerSource } from "@/lib/events.ts";
import { loadRecap, recapText } from "@/lib/recap.ts";
import { pickLocale, t } from "@/lib/i18n.ts";
import { isOpen, sealedCount } from "@/lib/coffin.ts";
import { walletConfigured } from "@/lib/wallet.ts";
import { getCountdown, memberCount, recordView, toPublic } from "@/lib/countdowns.ts";
import { linkFor, publicOrigin } from "@/lib/http.ts";
import { headline, previewKey } from "@/lib/time.ts";
import { isSlug } from "@/lib/validate.ts";
import { LiveCountdown } from "./LiveCountdown.tsx";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ slug: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> };

async function load(slug: string) {
  return isSlug(slug) ? getCountdown(slug) : null;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const doc = await load(slug);
  if (!doc) return { title: "Count Downcula" };
  const now = new Date();
  const locale = pickLocale((await headers()).get("accept-language"));
  const { value, caption } = headline(now, doc.targetDate, doc.kind, doc.timeZone, locale);
  const recap = await loadRecap(doc, now);
  // After zero the preview tells the story instead of the date: "It happened. 23 counted down together."
  const words = recap ? recapText(recap, doc.visibility === "public", locale) : null;
  const image = `${publicOrigin()}/c/${slug}/og?d=${previewKey(now, doc.targetDate, doc.kind)}${recap ? `&p=${recap.people}` : ""}`;
  const description = words && doc.kind !== "countUp"
    ? [t(locale, "itHappened"), words.together ?? words.counted].filter(Boolean).join(" ")
    : `${value} ${caption}`;
  return {
    title: `${doc.title} · Count Downcula`,
    description,
    openGraph: {
      title: doc.title,
      description,
      url: linkFor(doc),
      siteName: "Count Downcula",
      images: [{ url: image, width: 1200, height: 630, alt: `${doc.title}: ${description}` }],
      type: "website",
    },
    twitter: { card: "summary_large_image", title: doc.title, description, images: [image] },
    // Public crypt entries can be found in search; private links can't.
    robots: { index: doc.visibility === "public" },
    // Safari's App Clip card: open the countdown in the clip, no install needed.
    other: { "apple-itunes-app": "app-id=6820183254, app-clip-bundle-id=com.countdownula.app.Clip, app-clip-display=card" },
  };
}

export default async function CountdownPage({ params, searchParams }: Props) {
  const { slug } = await params;
  const doc = await load(slug);
  if (!doc) notFound();
  after(() => recordView(slug).catch(() => {}));
  // Where the view came from: a `?src=` the link was made with (the Wallet pass's QR code), or else
  // the referring site's host. Chat apps send no referrer, so most shared links show up as direct.
  const h = await headers();
  const src = (await searchParams).src;
  const source = typeof src === "string" ? src : referrerSource(h.get("referer"), new URL(publicOrigin()).hostname);
  after(() => logEvent("page_view", { headers: h }, { slug, source }));

  const photoURL = doc.hasPhoto ? `/c/${slug}/photo?v=${doc.updatedAt.getTime()}` : null;
  return (
    <LiveCountdown
      locale={pickLocale(h.get("accept-language"))}
      countdown={toPublic(doc)}
      photoURL={photoURL}
      serverNow={Date.now()}
      memberCount={await memberCount(slug)}
      sealed={isOpen(doc) ? 0 : await sealedCount(slug)}
      recap={await loadRecap(doc)}
      calendarURL={`${publicOrigin()}/c/${slug}/calendar.ics`}
      walletURL={walletConfigured() && doc.kind !== "countUp" ? `/c/${slug}/pass` : null}
    />
  );
}
