import type { Metadata } from "next";
import { CryptPage } from "./CryptPage.tsx";

export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: "The Crypt · Count Downcula",
  description: "Countdowns to holidays, eclipses, solstices and big games. Count down together.",
};

export default function Page() {
  return <CryptPage />;
}
