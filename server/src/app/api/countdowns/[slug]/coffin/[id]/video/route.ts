import { get, put } from "@vercel/blob";
import { NextResponse } from "next/server";
import { COFFIN_LIMITS, contributions, isOpen, loadCountdownAndRole, looksLikeVideo, parseId } from "@/lib/coffin.ts";
import { hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse } from "@/lib/http.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string; id: string }> };

/**
 * Adds a short video to your own note on a hosted countdown, before zero. The body is the raw
 * MP4 (under Vercel's request limit, so about 15 seconds at 720p); one video per note.
 */
export async function POST(request: Request, { params }: Context) {
  const { slug, id } = await params;
  const _id = parseId(id);
  if (!isSlug(slug) || !_id) return errorResponse(404, "Not found.");
  const token = bearer(request);
  const { doc, role } = await loadCountdownAndRole(slug, token);
  if (!doc || !role) return errorResponse(404, "Not found.");
  if (!doc.host) return errorResponse(402, "Videos in the coffin come with a Host Pass.");
  if (isOpen(doc)) return errorResponse(409, "The coffin is already open.");
  const collection = await contributions();
  const contribution = await collection.findOne({ _id, slug, removedAt: { $exists: false } });
  if (!contribution || contribution.authorTokenHash !== hashToken(token!)) return errorResponse(403, "Add a video to your own note.");
  if (contribution.videoPath) return errorResponse(409, "This note already has a video.");
  const length = Number(request.headers.get("content-length") ?? 0);
  if (length > COFFIN_LIMITS.videoBytes) return errorResponse(413, "That video is too long. Keep it to about 15 seconds.");
  const bytes = new Uint8Array(await request.arrayBuffer());
  if (bytes.length > COFFIN_LIMITS.videoBytes) return errorResponse(413, "That video is too long. Keep it to about 15 seconds.");
  if (!looksLikeVideo(bytes)) return errorResponse(422, "Send an MP4 or QuickTime video.");
  const videoPath = `coffin/${slug}/${id}.mp4`;
  await put(videoPath, Buffer.from(bytes), { access: "private", contentType: "video/mp4", addRandomSuffix: false });
  await collection.updateOne({ _id }, { $set: { videoPath } });
  return new NextResponse(null, { status: 201 });
}

/** The video: for its author any time, for everyone in the countdown after zero. */
export async function GET(request: Request, { params }: Context) {
  const { slug, id } = await params;
  const _id = parseId(id);
  if (!isSlug(slug) || !_id) return errorResponse(404, "Not found.");
  const token = bearer(request);
  const { doc, role } = await loadCountdownAndRole(slug, token);
  if (!doc || !role) return errorResponse(404, "Not found.");
  const contribution = await (await contributions()).findOne({ _id, slug, removedAt: { $exists: false } });
  if (!contribution?.videoPath) return errorResponse(404, "Not found.");
  if (!isOpen(doc) && contribution.authorTokenHash !== hashToken(token!)) return errorResponse(403, "Still sealed.");
  const blob = await get(contribution.videoPath, { access: "private" });
  if (!blob || blob.statusCode !== 200) return errorResponse(404, "Not found.");
  return new Response(blob.stream, { headers: { "Content-Type": "video/mp4", "Cache-Control": "private, max-age=3600" } });
}
