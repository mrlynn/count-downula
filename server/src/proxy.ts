import { NextResponse, type NextRequest } from "next/server";
import { metricsAuthorized } from "@/lib/adminAuth.ts";
import { resolveAlias } from "@/lib/host.ts";

/**
 * Two jobs before a request reaches its route:
 * - /admin/metrics asks for the dashboard password (the page checks it again).
 * - A hosted countdown's custom link (/c/sarah-and-tom, and the same name in its API and embed
 *   paths) is rewritten to the countdown's real slug, so every route works with either.
 */
export async function proxy(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (pathname === "/admin/metrics") {
    if (metricsAuthorized(request.headers.get("authorization"))) return NextResponse.next();
    return new NextResponse("Password required.", {
      status: 401,
      headers: { "WWW-Authenticate": 'Basic realm="Count Downcula metrics", charset="UTF-8"' },
    });
  }
  const match = /^\/(c|embed|api\/countdowns)\/([^/]+)(\/.*)?$/.exec(pathname);
  // Slugs mix cases, custom links are all lowercase: only those are worth a lookup.
  if (match && /^[a-z0-9-]+$/.test(match[2])) {
    const slug = await resolveAlias(match[2]).catch(() => null);
    if (slug) {
      const url = request.nextUrl.clone();
      url.pathname = `/${match[1]}/${slug}${match[3] ?? ""}`;
      return NextResponse.rewrite(url);
    }
  }
  return NextResponse.next();
}

export const config = { matcher: ["/admin/metrics", "/c/:path*", "/embed/:path*", "/api/countdowns/:path*"] };
