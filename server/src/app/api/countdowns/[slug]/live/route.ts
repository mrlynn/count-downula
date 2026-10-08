import { NextResponse } from "next/server";
import { roleFor } from "@/lib/coffin.ts";
import { getCountdown, hashToken } from "@/lib/countdowns.ts";
import { bearer, errorResponse, readJSON } from "@/lib/http.ts";
import { registerLiveDevice, validateRegistration } from "@/lib/live.ts";
import { isSlug } from "@/lib/validate.ts";

type Context = { params: Promise<{ slug: string }> };

/**
 * A phone in this shared countdown (owner or member) registers its push-to-start token and any
 * running Live Activity's token, so zero can reach it.
 */
export async function PUT(request: Request, { params }: Context) {
  const { slug } = await params;
  if (!isSlug(slug)) return errorResponse(404, "Not found.");
  const token = bearer(request);
  const doc = await getCountdown(slug);
  if (!doc) return errorResponse(404, "Not found.");
  if (!(await roleFor(doc, token))) return errorResponse(403, "Join this countdown first.");
  let body: unknown;
  try {
    body = await readJSON(request);
  } catch {
    return errorResponse(400, "Send a JSON body.");
  }
  const registration = validateRegistration(body);
  if (!registration.ok) return errorResponse(422, registration.error);
  await registerLiveDevice(slug, hashToken(token!), registration.value);
  return new NextResponse(null, { status: 204 });
}
