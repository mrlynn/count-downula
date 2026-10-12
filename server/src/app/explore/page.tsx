import type { Metadata } from "next";
import { headers } from "next/headers";
import { publicOrigin } from "@/lib/http.ts";
import { pickLocale, t } from "@/lib/i18n.ts";
import { CryptPage } from "./CryptPage.tsx";

export const dynamic = "force-dynamic";

export async function generateMetadata(): Promise<Metadata> {
  const locale = pickLocale((await headers()).get("accept-language"));
  return {
    title: `${t(locale, "crypt")} · Count Downcula`,
    description: t(locale, "cryptDescription"),
    alternates: { canonical: `${publicOrigin()}/explore` },
  };
}

export default function Page() {
  return <CryptPage />;
}
