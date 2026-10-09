import { NextResponse } from "next/server";
import { waitText, type Verdict } from "./rateLimit.ts";

export const publicOrigin = () => (process.env.PUBLIC_ORIGIN ?? "https://go.countdowncula.com").replace(/\/$/, "");

export const shareURL = (slug: string) => `${publicOrigin()}/c/${slug}`;

/** The link to hand out: the custom one when a host has set it. */
export const linkFor = (doc: { slug: string; alias?: string }) => shareURL(doc.alias ?? doc.slug);

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

/** Parses the JSON body, rejecting anything over `maxBytes` (1 MB unless said) before reading it all. */
export async function readJSON(request: Request, maxBytes = 1024 * 1024): Promise<unknown> {
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > maxBytes) throw new Error("too-large");
  const text = await request.text();
  if (text.length > maxBytes) throw new Error("too-large");
  return JSON.parse(text);
}
