import type { MetadataRoute } from "next";
import { publicOrigin } from "@/lib/http.ts";

// Private countdowns opt out page by page (robots noindex); these paths are never worth crawling.
export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: ["/api/", "/admin/", "/embed/", "/c/*/edit", "/c/*/present"] },
    sitemap: `${publicOrigin()}/sitemap.xml`,
  };
}
