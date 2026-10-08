import { NextResponse } from "next/server";
import { CATEGORIES, listCrypt } from "@/lib/crypt.ts";

/** The crypt for the app: current public countdowns with their subscriber counts. */
export async function GET(request: Request) {
  const category = new URL(request.url).searchParams.get("category") ?? undefined;
  const entries = await listCrypt(category);
  return NextResponse.json(
    { categories: CATEGORIES, entries },
    { headers: { "Cache-Control": "public, s-maxage=60, stale-while-revalidate=300" } },
  );
}
