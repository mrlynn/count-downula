import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import { Editor } from "@/app/new/Editor.tsx";
import { getCountdown, toPublic } from "@/lib/countdowns.ts";
import { editLinksEnabled } from "@/lib/email.ts";
import { pickLocale, t } from "@/lib/i18n.ts";
import { isSlug } from "@/lib/validate.ts";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ slug: string }> };

export async function generateMetadata(): Promise<Metadata> {
  const locale = pickLocale((await headers()).get("accept-language"));
  return { title: `${t(locale, "editTitle")} · Count Downcula`, robots: { index: false } };
}

/** Edits a countdown with the owner token this browser holds, or one an emailed link brings. */
export default async function EditPage({ params }: Props) {
  const { slug } = await params;
  const doc = isSlug(slug) ? await getCountdown(slug) : null;
  if (!doc) notFound();
  const locale = pickLocale((await headers()).get("accept-language"));
  return (
    <Editor
      locale={locale}
      existing={toPublic(doc)}
      photoURL={doc.hasPhoto ? `/c/${slug}/photo?v=${doc.updatedAt.getTime()}` : null}
      emailEnabled={editLinksEnabled()}
    />
  );
}
