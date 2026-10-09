import type { Metadata } from "next";
import { headers } from "next/headers";
import { after } from "next/server";
import { logEvent } from "@/lib/events.ts";
import { editLinksEnabled } from "@/lib/email.ts";
import { pickLocale, t } from "@/lib/i18n.ts";
import { Editor } from "./Editor.tsx";

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  const locale = pickLocale((await headers()).get("accept-language"));
  return { title: `${t(locale, "newTitle")} · Count Downcula`, description: t(locale, "newIntro") };
}

/** Make a countdown in the browser: for people without the iPhone app, Android and desktop alike. */
export default async function NewPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const h = await headers();
  const locale = pickLocale(h.get("accept-language"));
  const src = (await searchParams).src;
  after(() => logEvent("new_view", { headers: h }, { source: typeof src === "string" ? src : undefined }));
  return <Editor locale={locale} emailEnabled={editLinksEnabled()} />;
}
