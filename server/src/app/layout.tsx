import "@fontsource/young-serif/400.css";
import "@fontsource/instrument-sans/400.css";
import "@fontsource/instrument-sans/500.css";
import "@fontsource/instrument-sans/700.css";
import type { Metadata, Viewport } from "next";
import type { ReactNode } from "react";
import { publicOrigin } from "@/lib/http.ts";
import { Providers } from "./providers.tsx";

export const metadata: Metadata = {
  metadataBase: new URL(publicOrigin()),
  title: "Count Downcula",
  description: "Countdowns for the moments you can't wait for.",
};

export const viewport: Viewport = { themeColor: "#0F0508", colorScheme: "dark" };

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}
