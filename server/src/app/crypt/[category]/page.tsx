import type { Metadata } from "next";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import { pickLocale, t, type Key } from "@/lib/i18n.ts";
import { CATEGORIES } from "@/lib/crypt.ts";
import { CryptPage } from "../CryptPage.tsx";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ category: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { category } = await params;
  const locale = pickLocale((await headers()).get("accept-language"));
  const known = CATEGORIES.some((c) => c.slug === category);
  return { title: `${known ? t(locale, "categoryTitle", { name: t(locale, category as Key) }) : t(locale, "crypt")} · Count Downcula` };
}

export default async function Page({ params }: Props) {
  const { category } = await params;
  if (!CATEGORIES.some((c) => c.slug === category)) notFound();
  return <CryptPage category={category} />;
}
