import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { CATEGORIES } from "@/lib/crypt.ts";
import { CryptPage } from "../CryptPage.tsx";

export const dynamic = "force-dynamic";

type Props = { params: Promise<{ category: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { category } = await params;
  const name = CATEGORIES.find((c) => c.slug === category)?.name ?? "The Crypt";
  return { title: `${name} countdowns · Count Downcula` };
}

export default async function Page({ params }: Props) {
  const { category } = await params;
  if (!CATEGORIES.some((c) => c.slug === category)) notFound();
  return <CryptPage category={category} />;
}
