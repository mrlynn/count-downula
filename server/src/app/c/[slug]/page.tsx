import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { after } from "next/server";
import { isOpen, sealedCount } from "@/lib/coffin.ts";
import { walletConfigured } from "@/lib/wallet.ts";
import { getCountdown, memberCount, recordView, toPublic } from "@/lib/countdowns.ts";
import { publicOrigin } from "@/lib/http.ts";
import { headline, previewKey } from "@/lib/time.ts";
import { isSlug } from "@/lib/validate.ts";
import { LiveCountdown } from "./LiveCountdown.tsx";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ slug: string }> };

async function load(slug: string) {
  return isSlug(slug) ? getCountdown(slug) : null;
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { slug } = await params;
  const doc = await load(slug);
  if (!doc) return { title: "Count Downcula" };
  const now = new Date();
  const { value, caption } = headline(now, doc.targetDate, doc.kind, doc.timeZone);
  const image = `${publicOrigin()}/c/${slug}/og?d=${previewKey(now, doc.targetDate, doc.kind)}`;
  const description = `${value} ${caption}`;
  return {
    title: `${doc.title} · Count Downcula`,
    description,
    openGraph: {
      title: doc.title,
      description,
      url: `${publicOrigin()}/c/${slug}`,
      siteName: "Count Downcula",
      images: [{ url: image, width: 1200, height: 630, alt: `${doc.title}: ${description}` }],
      type: "website",
    },
    twitter: { card: "summary_large_image", title: doc.title, description, images: [image] },
    robots: { index: false },
    // Safari's App Clip card: open the countdown in the clip, no install needed.
    other: { "apple-itunes-app": "app-id=6820183254, app-clip-bundle-id=com.countdownula.app.Clip, app-clip-display=card" },
  };
}

export default async function CountdownPage({ params }: Props) {
  const { slug } = await params;
  const doc = await load(slug);
  if (!doc) notFound();
  after(() => recordView(slug).catch(() => {}));

  const photoURL = doc.hasPhoto ? `/c/${slug}/photo?v=${doc.updatedAt.getTime()}` : null;
  return (
    <LiveCountdown
      countdown={toPublic(doc)}
      photoURL={photoURL}
      serverNow={Date.now()}
      memberCount={await memberCount(slug)}
      sealed={isOpen(doc) ? 0 : await sealedCount(slug)}
      walletURL={walletConfigured() && doc.kind !== "countUp" ? `/c/${slug}/pass` : null}
    />
  );
}
