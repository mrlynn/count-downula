import { after } from "next/server";
import { logEvent } from "@/lib/events.ts";
import { buildPassForSlug, pkpassResponse } from "@/lib/walletPass.ts";
import { isSlug } from "@/lib/validate.ts";
import { walletConfigured } from "@/lib/wallet.ts";

/** "Add to Apple Wallet": the countdown as a pass. Anyone with the link can add it. */
export async function GET(request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  if (!walletConfigured()) return new Response("Wallet passes aren't set up yet.", { status: 503 });
  const built = isSlug(slug) ? await buildPassForSlug(slug) : null;
  if (!built) return new Response("Not found", { status: 404 });
  after(() => logEvent("wallet_pass_download", request, { slug }));
  return pkpassResponse(built.bytes, slug, built.updatedAt);
}
