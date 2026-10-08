import { put } from "@vercel/blob";
import { NextResponse } from "next/server";
import { COFFIN_LIMITS, contributions, isOpen, loadCountdownAndRole, toPublic, validateContribution } from "@/lib/coffin.ts";
import { hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse, readJSON, tooManyRequests } from "@/lib/http.ts";
import { checkLimits, clientSubject, limits } from "@/lib/rateLimit.ts";
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

/** Drop something in. Owner or member, before zero. */
export async function POST(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const token = bearer(request);
  const { doc, role } = await loadCountdownAndRole(slug, token);
  if (!doc) return errorResponse(404, "Not found.");
  if (!role) return errorResponse(403, "Join this countdown to add to its coffin.");
  if (doc.kind === "countUp") return errorResponse(422, "Count-ups don't have a coffin.");
  if (doc.visibility === "public") return errorResponse(422, "Public countdowns don't have a coffin.");
  if (isOpen(doc)) return errorResponse(409, "The coffin is already open.");

  const verdict = await checkLimits([
    [limits.contributionsPerHour, clientSubject(request)],
    [limits.contributionsPerCountdownPerHour, slug],
  ]);
  if (!verdict.ok) return tooManyRequests(verdict, "notes");

  let body: unknown;
  try {
    body = await readJSON(request);
  } catch {
    return errorResponse(400, "Send a JSON body under 1 MB.");
  }
  const input = validateContribution(body);
  if (!input.ok) return errorResponse(422, input.error);

  const collection = await contributions();
  if ((await collection.countDocuments({ slug, removedAt: { $exists: false } })) >= COFFIN_LIMITS.perCountdown) {
    return errorResponse(409, "This coffin is full.");
  }
  const _id = new ObjectId();
  let photoPath: string | undefined;
  if (input.value.photo) {
    photoPath = `coffin/${slug}/${_id.toHexString()}.jpg`;
    await put(photoPath, input.value.photo, { access: "private", contentType: "image/jpeg", addRandomSuffix: false });
  }
  const doc2 = {
    _id, slug, authorTokenHash: hashToken(token!), name: input.value.name, text: input.value.text,
    ...(photoPath ? { photoPath } : {}), createdAt: new Date(), reports: 0,
  };
  await collection.insertOne(doc2);
  return NextResponse.json(toPublic(doc2, doc2.authorTokenHash), { status: 201 });
}
