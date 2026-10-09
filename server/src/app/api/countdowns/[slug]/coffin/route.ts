import { put } from "@vercel/blob";
import { after, NextResponse } from "next/server";
import { addGuest, COFFIN_LIMITS, coffinRefusal, contributions, isOpen, loadCountdownAndRole, toPublic, validateContribution } from "@/lib/coffin.ts";
import { logEvent } from "@/lib/events.ts";
import { hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse, readJSON, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits, type Limit } from "@/lib/rateLimit.ts";
import { isSlug } from "@/lib/validate.ts";
import { ObjectId } from "mongodb";

type Context = { params: Promise<{ slug: string }> };

/**
 * Before zero: how many are sealed, plus the asker's own. After zero: everything, for the owner
 * and members only.
 */
export async function GET(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const token = bearer(request);
  const { doc, role } = await loadCountdownAndRole(slug, token);
  if (!doc) return errorResponse(404, "Not found.");
  const viewer = token ? hashToken(token) : null;
  const all = await (await contributions()).find({ slug, removedAt: { $exists: false } }).sort({ createdAt: 1 }).toArray();
  const open = isOpen(doc);
  const visible = open && role ? all : all.filter((c) => role && c.authorTokenHash === viewer);
  return NextResponse.json(
    {
      opensAt: doc.targetDate.toISOString(),
      open,
      sealedCount: all.length,
      role,
      contributions: visible.map((c) => toPublic(c, viewer)),
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}

/**
 * Drop something in, before zero. The owner and members send their key from the app. A browser
 * sends the guest key it got with its first drop, or nothing, and gets one back.
 */
export async function POST(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const sent = bearer(request);
  const { doc, role } = await loadCountdownAndRole(slug, sent);
  if (!doc) return errorResponse(404, "Not found.");
  const refusal = coffinRefusal(doc);
  if (refusal) return errorResponse(isOpen(doc) ? 409 : 422, refusal);

  const client = clientSubject(request);
  const isGuest = role === null || role === "guest";
  const checks: [Limit, string][] = [
    [limits.contributionsPerHour, client],
    [limits.contributionsPerCountdownPerHour, slug],
  ];
  if (isGuest) checks.push([limits.guestContributionsPerHour, client], [limits.guestContributionsPerCountdownPerHour, slug]);
  const verdict = await checkLimits(checks);
  if (!verdict.ok) return tooManyRequests(verdict, "notes");

  // A hosted countdown's notes can carry several photos, so it takes a bigger body.
  const maxPhotos = doc.host ? COFFIN_LIMITS.hostPhotos : COFFIN_LIMITS.photos;
  let body: unknown;
  try {
    body = await readJSON(request, doc.host ? 4 * 1024 * 1024 : 1024 * 1024);
  } catch {
    return errorResponse(400, doc.host ? "Send a JSON body under 4 MB." : "Send a JSON body under 1 MB.");
  }
  const input = validateContribution(body, maxPhotos);
  if (!input.ok) return errorResponse(422, input.error);

  const collection = await contributions();
  if ((await collection.countDocuments({ slug, removedAt: { $exists: false } })) >= COFFIN_LIMITS.perCountdown) {
    return errorResponse(409, "This coffin is full.");
  }
  // A browser's first drop: a key of its own, kept in its storage, to see and remove it later.
  const issued = role === null ? await addGuest(slug) : null;
  const token = issued?.token ?? sent!;
  const _id = new ObjectId();
  const photoPaths = input.value.photos.map((_, i) => `coffin/${slug}/${_id.toHexString()}${i ? `-${i}` : ""}.jpg`);
  await Promise.all(input.value.photos.map((photo, i) =>
    put(photoPaths[i], photo, { access: "private", contentType: "image/jpeg", addRandomSuffix: false })));
  const photoPath = photoPaths[0];
  const doc2 = {
    _id, slug, authorTokenHash: issued?.tokenHash ?? hashToken(token), name: input.value.name, text: input.value.text,
    ...(photoPath ? { photoPath } : {}), ...(photoPaths.length > 1 ? { photoPaths } : {}), createdAt: new Date(), reports: 0,
  };
  await collection.insertOne(doc2);
  after(() => logEvent("coffin_drop", request, { slug, source: photoPath ? "photo" : "note" }));
  return NextResponse.json(
    { ...toPublic(doc2, doc2.authorTokenHash), ...(issued ? { token: issued.token } : {}) },
    { status: 201 },
  );
}
