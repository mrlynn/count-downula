import { NextResponse } from "next/server";
import { getCountdown, hashToken } from "@/lib/countdowns.ts";
import { parseId } from "@/lib/coffin.ts";
import { bearer, errorResponse } from "@/lib/http.ts";
import { guesses } from "@/lib/pool.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string; id: string }> };

/** Takes a guess back: its guesser, or the owner, while the pool is unsettled. */
export async function DELETE(request: Request, { params }: Context) {
  const { slug, id } = await params;
  const _id = parseId(id);
  if (!isSlug(slug) || !_id) return errorResponse(404, "Not found.");
  const doc = await getCountdown(slug);
  if (!doc?.pool) return errorResponse(404, "Not found.");
  if (doc.pool.answer) return errorResponse(409, "This pool is already settled.");
  const token = bearer(request);
  if (!token) return errorResponse(403, "That isn't your guess.");
  const hash = hashToken(token);
  const collection = await guesses();
  const guess = await collection.findOne({ _id, slug });
  if (!guess) return errorResponse(404, "Not found.");
  if (guess.tokenHash !== hash && hash !== doc.ownerTokenHash) return errorResponse(403, "That isn't your guess.");
  await collection.deleteOne({ _id });
  return new NextResponse(null, { status: 204 });
}
