import { after, NextResponse } from "next/server";
import { getCountdown, hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse, readJSON } from "@/lib/http.ts";
import { notifyMembers } from "@/lib/notify.ts";
import { poolGuesses, validatePoolAction } from "@/lib/pool.ts";
import { pushPassUpdates } from "@/lib/walletPass.ts";
import { db } from "@/lib/mongo.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

/** The pool and every guess. Guesses are public to anyone with the link, like the countdown. */
export async function GET(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const doc = await getCountdown(slug);
  if (!doc?.pool) return errorResponse(404, "Not found.");
  const token = bearer(request);
  return NextResponse.json(
    {
      closed: doc.pool.closed,
      answer: doc.pool.answer?.toISOString() ?? null,
      isOwner: token ? hashToken(token) === doc.ownerTokenHash : false,
      guesses: await poolGuesses(doc, token),
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}

/** The owner closes or reopens guessing, or sets the real date, which settles the pool. */
export async function PUT(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const doc = await getCountdown(slug);
  if (!doc?.pool) return errorResponse(404, "Not found.");
  const token = bearer(request);
  if (!token || hashToken(token) !== doc.ownerTokenHash) return errorResponse(403, "Only the owner can do that.");
  let body: unknown;
  try {
    body = await readJSON(request);
  } catch {
    return errorResponse(400, "Send a JSON body.");
  }
  const action = validatePoolAction(body);
  if (!action.ok) return errorResponse(422, action.error);
  const countdowns = (await db()).collection("countdowns");
  const now = new Date();
  switch (action.value.action) {
    case "close":
      await countdowns.updateOne({ slug }, { $set: { "pool.closed": true, updatedAt: now } });
      break;
    case "reopen":
      if (doc.pool.answer) return errorResponse(409, "This pool is already settled.");
      await countdowns.updateOne({ slug }, { $set: { "pool.closed": false, updatedAt: now } });
      break;
    case "settle":
      // The countdown fills in: it now counts to (or from) the real date.
      await countdowns.updateOne({ slug }, {
        $set: {
          "pool.closed": true, "pool.answer": action.value.answer, "pool.settledAt": now,
          targetDate: action.value.answer, updatedAt: now,
        },
      });
      break;
  }
  after(() => notifyMembers(slug).catch(() => {}));
  after(() => pushPassUpdates(slug).catch(() => {}));
  const updated = await getCountdown(slug);
  return NextResponse.json({
    closed: updated!.pool!.closed,
    answer: updated!.pool!.answer?.toISOString() ?? null,
    isOwner: true,
    guesses: await poolGuesses(updated!, token),
  });
}
