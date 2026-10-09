import { NextResponse, type NextRequest } from "next/server";
import { metricsAuthorized } from "@/lib/adminAuth.ts";

/** Asks the browser for the dashboard password. The page checks it again before reading anything. */
export function proxy(request: NextRequest) {
  if (metricsAuthorized(request.headers.get("authorization"))) return NextResponse.next();
  return new NextResponse("Password required.", {
    status: 401,
    headers: { "WWW-Authenticate": 'Basic realm="Count Downcula metrics", charset="UTF-8"' },
  });
}

export const config = { matcher: "/admin/metrics" };
