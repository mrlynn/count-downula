import { NextResponse } from "next/server";
import { waitText, type Verdict } from "./rateLimit.ts";

export const publicOrigin = () => (process.env.PUBLIC_ORIGIN ?? "https://go.countdowncula.com").replace(/\/$/, "");

export const shareURL = (slug: string) => `${publicOrigin()}/c/${slug}`;

export const errorResponse = (status: number, error: string) => NextResponse.json({ error }, { status });

/** 429 with a Retry-After header and a message the app can show as is. */
export function tooManyRequests(verdict: Extract<Verdict, { ok: false }>, doing: string): NextResponse {
  return NextResponse.json(
    { error: `Too many ${doing} for now. Try again in ${waitText(verdict.retryAfter)}.` },
    { status: 429, headers: { "Retry-After": String(verdict.retryAfter) } },
  );
}

export function bearer(request: Request): string | null {
  const header = request.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  return match ? match[1].trim() : null;
}

/** Parses the JSON body, rejecting anything over 1 MB before reading it all. */
export async function readJSON(request: Request): Promise<unknown> {
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > 1024 * 1024) throw new Error("too-large");
  const text = await request.text();
  if (text.length > 1024 * 1024) throw new Error("too-large");
  return JSON.parse(text);
}
