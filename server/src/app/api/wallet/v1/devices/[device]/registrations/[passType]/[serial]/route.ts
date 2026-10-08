import { NextResponse } from "next/server";
import { authorized, PASS_TYPE_ID } from "@/lib/wallet.ts";
import { registerPass, unregisterPass } from "@/lib/walletPass.ts";

type Context = { params: Promise<{ device: string; passType: string; serial: string }> };

/** Wallet registers a device for updates to a pass. */
export async function POST(request: Request, { params }: Context) {
  const { device, passType, serial } = await params;
  if (passType !== PASS_TYPE_ID || !authorized(request.headers.get("authorization"), serial)) {
    return new NextResponse(null, { status: 401 });
  }
  let pushToken = "";
  try {
    pushToken = String(((await request.json()) as { pushToken?: unknown }).pushToken ?? "");
  } catch {}
  if (!/^[0-9a-f]{32,512}$/i.test(pushToken) || device.length > 128) return new NextResponse(null, { status: 400 });
  const created = await registerPass(device, serial, pushToken);
  return new NextResponse(null, { status: created ? 201 : 200 });
}

/** The pass was removed from Wallet. */
export async function DELETE(request: Request, { params }: Context) {
  const { device, passType, serial } = await params;
  if (passType !== PASS_TYPE_ID || !authorized(request.headers.get("authorization"), serial)) {
    return new NextResponse(null, { status: 401 });
  }
  await unregisterPass(device, serial);
  return new NextResponse(null, { status: 200 });
}
