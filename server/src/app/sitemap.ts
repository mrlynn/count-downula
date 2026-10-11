import type { MetadataRoute } from "next";
import { CATEGORIES, listCrypt } from "@/lib/crypt.ts";
import { linkFor, publicOrigin } from "@/lib/http.ts";

// Only the public crypt: shared links are private and stay out of search.
export const dynamic = "force-dynamic";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const origin = publicOrigin();
  const entries = await listCrypt();
  return [
    { url: `${origin}/crypt`, changeFrequency: "daily" },
    ...CATEGORIES.map((c) => ({ url: `${origin}/crypt/${c.slug}`, changeFrequency: "daily" as const })),
    ...entries.map(({ countdown }) => ({ url: linkFor(countdown), lastModified: new Date(countdown.updatedAt) })),
  ];
}
