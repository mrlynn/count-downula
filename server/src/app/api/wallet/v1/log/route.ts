import { NextResponse } from "next/server";

/** Wallet reports problems with the web service here; they show up in Vercel's logs. */
export async function POST(request: Request) {
  try {
    const { logs } = (await request.json()) as { logs?: string[] };
    for (const line of (logs ?? []).slice(0, 20)) console.warn(`Wallet: ${String(line).slice(0, 500)}`);
  } catch {}
  return new NextResponse(null, { status: 200 });
}
