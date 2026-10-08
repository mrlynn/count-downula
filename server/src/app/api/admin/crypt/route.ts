import { timingSafeEqual } from "node:crypto";
import { NextResponse } from "next/server";
import { upsertCrypt, validateCryptEntry } from "@/lib/crypt.ts";
import { bearer, readJSON } from "@/lib/http.ts";

/** Loads or updates curated crypt entries. Needs CRYPT_ADMIN_TOKEN. */
export async function PUT(request: Request) {
  const expected = process.env.CRYPT_ADMIN_TOKEN ?? "";
  const given = bearer(request) ?? "";
  const ok = expected.length >= 32 && given.length === expected.length && timingSafeEqual(Buffer.from(given), Buffer.from(expected));
  if (!ok) return new NextResponse("Unauthorized", { status: 401 });
  let body: unknown;
  try {
    body = await readJSON(request);
  } catch {
    return NextResponse.json({ error: "Send a JSON array." }, { status: 400 });
  }
  if (!Array.isArray(body)) return NextResponse.json({ error: "Send a JSON array." }, { status: 400 });
  const checked = body.map(validateCryptEntry);
  const errors = checked.flatMap((c) => (c.ok ? [] : [c.error]));
  if (errors.length) return NextResponse.json({ errors }, { status: 422 });
  await upsertCrypt(checked.map((c) => (c as { value: Parameters<typeof upsertCrypt>[0][number] }).value));
  return NextResponse.json({ upserted: checked.length });
}
