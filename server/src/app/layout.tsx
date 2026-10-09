import "@fontsource/young-serif/400.css";
import "@fontsource/instrument-sans/400.css";
import "@fontsource/instrument-sans/500.css";
import "@fontsource/instrument-sans/700.css";
import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import type { ReactNode } from "react";
import { pickLocale } from "@/lib/i18n.ts";
import { publicOrigin } from "@/lib/http.ts";
import { Providers } from "./providers.tsx";

export const metadata: Metadata = {
  metadataBase: new URL(publicOrigin()),
  title: "Count Downcula",
  description: "Countdowns for the moments you can't wait for.",
};

export const viewport: Viewport = { themeColor: "#0F0508", colorScheme: "dark" };

export default async function RootLayout({ children }: { children: ReactNode }) {
  // Pages speak the browser's language (lib/i18n.ts); the lang attribute says which.
  const locale = pickLocale((await headers()).get("accept-language"));
  return (
    <html lang={locale}>
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
