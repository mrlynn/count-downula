import { after, NextResponse } from "next/server";
import { ObjectId } from "mongodb";
import { logEvent } from "@/lib/events.ts";
import { getCountdown, hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse, readJSON, tooManyRequests } from "@/lib/http.ts";
import { guesses, newGuesserToken, POOL_LIMITS, validateGuess } from "@/lib/pool.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

/**
 * Makes or changes your guess: one per guesser. The app sends its owner or member key; a browser
 * sends the key it got with its first guess, or nothing, and gets one back.
 */
export async function POST(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const doc = await getCountdown(slug);
  if (!doc?.pool) return errorResponse(404, "Not found.");
  if (doc.pool.closed) return errorResponse(409, "Guessing is closed.");

  const verdict = await checkLimits([
    [limits.guessesPerHour, clientSubject(request)],
    [limits.guessesPerPoolPerHour, slug],
  ]);
  if (!verdict.ok) return tooManyRequests(verdict, "guesses");

  let body: unknown;
  try {
    body = await readJSON(request);
  } catch {
    return errorResponse(400, "Send a JSON body.");
  }
  const input = validateGuess(body);
  if (!input.ok) return errorResponse(422, input.error);

  const sent = bearer(request);
  const issued = sent ? null : newGuesserToken();
  const tokenHash = hashToken(sent ?? issued!);
  const collection = await guesses();
  const existing = await collection.findOne({ slug, tokenHash });
  if (!existing && (await collection.countDocuments({ slug })) >= POOL_LIMITS.perPool) {
    return errorResponse(409, "This pool is full.");
  }
  const now = new Date();
  const saved = await collection.findOneAndUpdate(
    { slug, tokenHash },
    {
      $set: { name: input.value.name, guess: input.value.guess, updatedAt: now },
      $setOnInsert: { _id: new ObjectId(), createdAt: now },
    },
    { upsert: true, returnDocument: "after" },
  );
  if (!existing) after(() => logEvent("pool_guess", request, { slug }));
  return NextResponse.json(
    {
      guess: { id: saved!._id.toHexString(), name: saved!.name, guess: saved!.guess.toISOString(), mine: true },
      ...(issued ? { token: issued } : {}),
    },
    { status: existing ? 200 : 201 },
  );
}
