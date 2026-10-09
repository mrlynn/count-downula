"use client";

import { Alert, Box, Button, Stack, TextField, Typography } from "@mui/material";
import { useCallback, useEffect, useRef, useState } from "react";
import { t, type Locale } from "@/lib/i18n.ts";

interface Contribution {
  id: string;
  name: string;
  text: string;
  hasPhoto: boolean;
  photoCount?: number;
  hasVideo?: boolean;
  createdAt: string;
  mine: boolean;
}

interface CoffinState {
  open: boolean;
  sealedCount: number;
  role: "owner" | "member" | "guest" | null;
  contributions: Contribution[];
}

// The guest key the server hands this browser with its first drop, so it can see and remove its
// drops and open the coffin at zero. The name is shared with date pools.
const tokenKey = (slug: string) => `coffin-token:${slug}`;
const nameKey = "pool-name";
const NOTE_LIMIT = 500;
const PHOTO_BYTES = 400 * 1024;

function storage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

/** A photo as a base64 JPEG of at most 1080px and 400 KB, which is what the server takes. */
async function jpegBase64(file: File): Promise<string> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1080 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")!.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  for (const quality of [0.82, 0.7, 0.55, 0.4]) {
    const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
    if (blob && blob.size <= PHOTO_BYTES) {
      const bytes = new Uint8Array(await blob.arrayBuffer());
      let binary = "";
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      return btoa(binary);
    }
  }
  throw new Error("That photo is too large.");
}

/** A contribution's photo or video, fetched with the guest key since they're private. */
function useMedia(path: string, token: string): string | null {
  const [url, setURL] = useState<string | null>(null);
  useEffect(() => {
    let objectURL: string | null = null;
    fetch(path, { headers: { Authorization: `Bearer ${token}` } })
      .then((res) => (res.ok ? res.blob() : null))
      .then((blob) => {
        if (!blob) return;
        objectURL = URL.createObjectURL(blob);
        setURL(objectURL);
      })
      .catch(() => {});
    return () => {
      if (objectURL) URL.revokeObjectURL(objectURL);
    };
  }, [path, token]);
  return url;
}

function Photo({ slug, id, index = 0, token }: { slug: string; id: string; index?: number; token: string }) {
  const url = useMedia(`/api/countdowns/${slug}/coffin/${id}/photo?i=${index}`, token);
  return url ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={url} alt="" style={{ width: "100%", borderRadius: 12, display: "block", marginTop: 8 }} />
  ) : null;
}

function Video({ slug, id, token }: { slug: string; id: string; token: string }) {
  const url = useMedia(`/api/countdowns/${slug}/coffin/${id}/video`, token);
  return url ? <video src={url} controls playsInline style={{ width: "100%", borderRadius: 12, display: "block", marginTop: 8 }} /> : null;
}

/** Every photo a note has, then its video. */
function Media({ slug, c, token }: { slug: string; c: Contribution; token: string }) {
  const count = c.photoCount ?? (c.hasPhoto ? 1 : 0);
  return (
    <>
      {Array.from({ length: count }, (_, i) => <Photo key={i} slug={slug} id={c.id} index={i} token={token} />)}
      {c.hasVideo ? <Video slug={slug} id={c.id} token={token} /> : null}
    </>
  );
}

/**
 * The sealed coffin on the live page. Before zero anyone with the link can leave a note and a
 * photo; it stays sealed until zero, when everyone who left something sees what's inside.
 */
export default function CoffinPanel({ slug, opensAt, initialSealed, maxPhotos = 1, locale = "en" }: {
  slug: string;
  opensAt: string;
  initialSealed: number;
  /** One, or several on a hosted countdown. */
  maxPhotos?: number;
  locale?: Locale;
}) {
  const [state, setState] = useState<CoffinState | null>(null);
  const [token, setToken] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [text, setText] = useState("");
  const [photos, setPhotos] = useState<File[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [reported, setReported] = useState<string[]>([]);
  const fileInput = useRef<HTMLInputElement>(null);

  const load = useCallback(async () => {
    const key = storage()?.getItem(tokenKey(slug)) ?? null;
    setToken(key);
    const res = await fetch(`/api/countdowns/${slug}/coffin`, { headers: key ? { Authorization: `Bearer ${key}` } : {} });
    if (res.ok) setState(await res.json());
  }, [slug]);

  useEffect(() => {
    setName(storage()?.getItem(nameKey) ?? "");
    load();
  }, [load]);

  // Opens on its own when zero arrives with the page open.
  useEffect(() => {
    const wait = new Date(opensAt).getTime() - Date.now();
    if (wait <= 0 || wait > 2 ** 31 - 1) return;
    const id = setTimeout(load, wait + 1500);
    return () => clearTimeout(id);
  }, [opensAt, load]);

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    setError(null);
    setSaving(true);
    try {
      const body: Record<string, string> = { name: name.trim(), text: text.trim() };
      const encoded = await Promise.all(photos.map(jpegBase64));
      const payload: Record<string, string | string[]> = { ...body, ...(encoded.length ? { photos: encoded } : {}) };
      const res = await fetch(`/api/countdowns/${slug}/coffin`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(payload),
      });
      const reply = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(reply.error ?? t(locale, "couldntSeal"));
        return;
      }
      if (reply.token) storage()?.setItem(tokenKey(slug), reply.token);
      storage()?.setItem(nameKey, name.trim());
      setText("");
      setPhotos([]);
      if (fileInput.current) fileInput.current.value = "";
      await load();
    } catch (err) {
      setError(err instanceof Error && err.message !== "That photo is too large." ? err.message
        : err instanceof Error ? t(locale, "photoTooLarge") : t(locale, "couldntReadPhoto"));
    } finally {
      setSaving(false);
    }
  }

  async function remove(id: string) {
    if (!token) return;
    await fetch(`/api/countdowns/${slug}/coffin/${id}`, { method: "DELETE", headers: { Authorization: `Bearer ${token}` } });
    await load();
  }

  async function report(id: string) {
    if (!token) return;
    await fetch(`/api/countdowns/${slug}/coffin/${id}/report`, { method: "POST", headers: { Authorization: `Bearer ${token}` } });
    setReported((r) => [...r, id]);
  }

  const open = state?.open ?? new Date(opensAt) <= new Date();
  const sealed = state?.sealedCount ?? initialSealed;
  const mine = state?.contributions.filter((c) => c.mine) ?? [];
  const canSee = open && state?.role;

  return (
    <Box sx={{ bgcolor: "background.paper", px: { xs: 2, sm: 4 }, py: { xs: 4, sm: 5 }, borderTop: "1px solid rgba(255,255,255,0.06)" }}>
      <Box sx={{ maxWidth: 960, mx: "auto" }}>
        <Typography variant="h2" sx={{ fontFamily: `"Young Serif", Georgia, serif`, fontSize: { xs: 26, sm: 32 }, mb: 1 }}>
          {t(locale, open ? "coffinOpen" : "coffinSealed")}
        </Typography>
        <Typography sx={{ opacity: 0.75, mb: 3 }}>
          {open
            ? canSee
              ? sealed === 0
                ? t(locale, "coffinNothingLeft")
                : t(locale, "coffinFromEveryone", { n: sealed })
              : t(locale, "coffinWasSealed", { n: sealed })
            : `${sealed === 0 ? t(locale, "coffinNothingYet") : t(locale, "coffinSoFar", { n: sealed })} ${t(locale, "coffinInvite")}`}
        </Typography>

        {!open ? (
          <Stack component="form" onSubmit={submit} spacing={1.5} sx={{ mb: 3, maxWidth: 560 }}>
            <TextField label={t(locale, "yourName")} value={name} onChange={(e) => setName(e.target.value.slice(0, 40))} required size="small" />
            <TextField
              label={t(locale, "yourNote")}
              value={text}
              onChange={(e) => setText(e.target.value.slice(0, NOTE_LIMIT))}
              multiline
              minRows={3}
              helperText={`${text.length}/${NOTE_LIMIT}`}
            />
            <Stack direction="row" spacing={1.5} sx={{ alignItems: "center" }}>
              <Button component="label" variant="outlined">
                {photos.length ? t(locale, maxPhotos > 1 ? "changePhotos" : "changePhoto")
                  : maxPhotos > 1 ? t(locale, "addPhotos", { n: maxPhotos }) : t(locale, "addPhoto")}
                <input ref={fileInput} hidden type="file" accept="image/*" multiple={maxPhotos > 1}
                       onChange={(e) => setPhotos(Array.from(e.target.files ?? []).slice(0, maxPhotos))} />
              </Button>
              {photos.length ? (
                <Typography sx={{ opacity: 0.7, overflow: "hidden", textOverflow: "ellipsis" }}>
                  {photos.length === 1 ? photos[0].name : t(locale, "photos", { n: photos.length })}
                </Typography>
              ) : null}
            </Stack>
            <Box>
              <Button type="submit" variant="contained" disabled={saving || !name.trim() || (!text.trim() && photos.length === 0)}>
                {t(locale, saving ? "sealing" : "sealIt")}
              </Button>
            </Box>
            {error ? <Alert severity="error">{error}</Alert> : null}
          </Stack>
        ) : null}

        {!open && mine.length > 0 && token ? (
          <Stack spacing={1}>
            <Typography sx={{ fontWeight: 600, opacity: 0.8 }}>{t(locale, "whatYouSealed")}</Typography>
            {mine.map((c) => (
              <Box key={c.id} sx={{ px: 2, py: 1.5, borderRadius: 2, bgcolor: "rgba(127,127,127,0.08)" }}>
                {c.text ? <Typography sx={{ whiteSpace: "pre-wrap" }}>{c.text}</Typography> : null}
                <Media slug={slug} c={c} token={token} />
                <Button size="small" color="inherit" sx={{ mt: 1, opacity: 0.7 }} onClick={() => remove(c.id)}>
                  {t(locale, "remove")}
                </Button>
              </Box>
            ))}
          </Stack>
        ) : null}

        {canSee && token && state ? (
          <Box sx={{ display: "grid", gap: 1.5, gridTemplateColumns: { xs: "1fr", sm: "1fr 1fr" } }}>
            {state.contributions.map((c) => (
              <Box key={c.id} sx={{ px: 2, py: 1.5, borderRadius: 2, bgcolor: "rgba(127,127,127,0.08)" }}>
                <Typography sx={{ fontWeight: 600 }}>
                  {c.name}
                  {c.mine ? ` ${t(locale, "you")}` : ""}
                </Typography>
                {c.text ? <Typography sx={{ whiteSpace: "pre-wrap", mt: 0.5 }}>{c.text}</Typography> : null}
                <Media slug={slug} c={c} token={token} />
                {!c.mine ? (
                  <Button size="small" color="inherit" sx={{ mt: 1, opacity: 0.6 }} disabled={reported.includes(c.id)} onClick={() => report(c.id)}>
                    {t(locale, reported.includes(c.id) ? "reported" : "report")}
                  </Button>
                ) : null}
              </Box>
            ))}
          </Box>
        ) : null}
      </Box>
    </Box>
  );
}
