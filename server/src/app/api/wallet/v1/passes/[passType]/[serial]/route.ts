import { NextResponse } from "next/server";
import { authorized, PASS_TYPE_ID, walletConfigured } from "@/lib/wallet.ts";
import { buildPassForSlug, pkpassResponse } from "@/lib/walletPass.ts";

type Context = { params: Promise<{ passType: string; serial: string }> };

/** Wallet fetches the latest version of a pass. */
export async function GET(request: Request, { params }: Context) {
  const { passType, serial } = await params;
  if (passType !== PASS_TYPE_ID || !authorized(request.headers.get("authorization"), serial)) {
    return new NextResponse(null, { status: 401 });
  }
  if (!walletConfigured()) return new NextResponse(null, { status: 503 });
  const built = await buildPassForSlug(serial);
  if (!built) return new NextResponse(null, { status: 404 });
  const since = request.headers.get("if-modified-since");
  if (since && Math.floor(built.updatedAt.getTime() / 1000) <= Math.floor(new Date(since).getTime() / 1000)) {
    return new NextResponse(null, { status: 304 });
  }
  return pkpassResponse(built.bytes, serial, built.updatedAt);
}
