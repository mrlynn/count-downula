import { NextResponse } from "next/server";
import { PASS_TYPE_ID } from "@/lib/wallet.ts";
import { serialsForDevice } from "@/lib/walletPass.ts";

type Context = { params: Promise<{ device: string; passType: string }> };

/** After a push, Wallet asks which of its passes changed. */
export async function GET(request: Request, { params }: Context) {
  const { device, passType } = await params;
  if (passType !== PASS_TYPE_ID) return new NextResponse(null, { status: 404 });
  const since = new URL(request.url).searchParams.get("passesUpdatedSince");
  const { serials, lastUpdated } = await serialsForDevice(device, since ? Number(since) : undefined);
  if (serials.length === 0) return new NextResponse(null, { status: 204 });
  return NextResponse.json({ serialNumbers: serials, lastUpdated: String(lastUpdated) });
}
