"use client";

import { Alert, Box, Button, MenuItem, Stack, TextField, Typography } from "@mui/material";
import { useEffect, useMemo, useRef, useState } from "react";
import type { PublicCountdown } from "@/lib/countdowns.ts";
import { t, type Key, type Locale } from "@/lib/i18n.ts";
import { gradientCss, type RGBA } from "@/lib/style.ts";
import type { Unit } from "@/lib/units.ts";
import {
  countdownPayload, lookOf, OWNER_KEY, tokenFromHash, WEB_GRADIENTS, WEB_SCENES, zonedFields,
  type FormError, type Look,
} from "@/lib/webCreate.ts";
import { EmailEditLink } from "./EmailEditLink.tsx";

const UNITS: [Unit, Key][] = [
  ["daysHours", "unitDaysHours"], ["weeks", "unitWeeks"], ["sleeps", "unitSleeps"],
  ["workdays", "unitWorkdays"], ["weekends", "unitWeekends"], ["percent", "unitPercent"],
];
const ERRORS: Record<FormError, Key> = { title: "errTitle", date: "errDate", past: "errPast" };

/** The tokens this browser holds, by slug. */
export function ownedTokens(): Record<string, string> {
  try {
    return JSON.parse(localStorage.getItem(OWNER_KEY) ?? "{}") as Record<string, string>;
  } catch {
    return {};
  }
}

export function rememberToken(slug: string, token: string | null) {
  try {
    const owned = ownedTokens();
    if (token) owned[slug] = token; else delete owned[slug];
    localStorage.setItem(OWNER_KEY, JSON.stringify(owned));
  } catch {}
}

/** A photo as base64 JPEG under the server's 400 KB: scaled to 1080 px and recompressed until it fits. */
async function preparePhoto(file: File): Promise<string | null> {
  const bitmap = await createImageBitmap(file);
  const scale = Math.min(1, 1080 / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.round(bitmap.width * scale);
  canvas.height = Math.round(bitmap.height * scale);
  canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  for (const quality of [0.85, 0.75, 0.62, 0.5]) {
    const data = canvas.toDataURL("image/jpeg", quality).split(",")[1];
    if (data.length * 0.75 < 390 * 1024) return data;
  }
  return null;
}

const gradientPreview = (stops: number[], angle: number) =>
  gradientCss({
    stops: stops.map((n): RGBA => ({ red: ((n >> 16) & 255) / 255, green: ((n >> 8) & 255) / 255, blue: (n & 255) / 255 })),
    angle,
  });

/**
 * The web editor: title, date and time in a zone, details, a look (a scene, a gradient or a photo)
 * and a unit. Creates through the same publish API as the app and keeps the owner token in this
 * browser; edits with it.
 */
export function Editor({
  locale,
  existing = null,
  photoURL = null,
  emailEnabled = false,
}: {
  locale: Locale;
  /** Set when editing. */
  existing?: PublicCountdown | null;
  photoURL?: string | null;
  emailEnabled?: boolean;
}) {
  const [token, setToken] = useState<string | null>(null);
  const [ready, setReady] = useState(!existing);
  const [zones, setZones] = useState<string[]>([]);
  const [title, setTitle] = useState(existing?.title ?? "");
  const [details, setDetails] = useState(existing?.details ?? "");
  const [timeZone, setTimeZone] = useState(existing?.timeZone ?? "UTC");
  const [date, setDate] = useState("");
  const [time, setTime] = useState("00:00");
  const [look, setLook] = useState<Look>(existing ? lookOf(existing.style) : { scene: "birthday" });
  const [unit, setUnit] = useState<Unit>((existing?.unit as Unit | undefined) ?? "daysHours");
  const [photo, setPhoto] = useState<string | null>(null);
  const [preview, setPreview] = useState<string | null>(photoURL);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [created, setCreated] = useState<string | null>(null);
  const fileInput = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone;
    try {
      setZones((Intl as unknown as { supportedValuesOf: (k: string) => string[] }).supportedValuesOf("timeZone"));
    } catch {
      setZones([zone]);
    }
    if (existing) {
      // An emailed link carries the token in the fragment; keep it here and take it out of the address bar.
      const fromLink = tokenFromHash(window.location.hash);
      if (fromLink) {
        rememberToken(existing.slug, fromLink);
        history.replaceState(null, "", window.location.pathname);
      }
      setToken(fromLink ?? ownedTokens()[existing.slug] ?? null);
      const fields = zonedFields(new Date(existing.targetDate), existing.timeZone);
      setDate(fields.date);
      setTime(fields.time);
      setReady(true);
    } else {
      setTimeZone(zone);
      const week = new Date(Date.now() + 7 * 86_400_000);
      setDate(zonedFields(week, zone).date);
      setTime("18:00");
    }
  }, [existing]);

  const backdrop = useMemo(() => {
    if ("photo" in look) return preview ? `center / cover no-repeat url(${preview})` : gradientPreview(WEB_GRADIENTS[0].stops, 45);
    if ("scene" in look) return `center / cover no-repeat url(/scenes/${look.scene}.jpg)`;
    const g = WEB_GRADIENTS.find((x) => x.id === look.gradient) ?? WEB_GRADIENTS[0];
    return gradientPreview(g.stops, g.angle);
  }, [look, preview]);

  async function choosePhoto(file: File | undefined) {
    if (!file) return;
    const data = await preparePhoto(file).catch(() => null);
    if (!data) return setError(t(locale, "photoTooBig"));
    setPhoto(data);
    setPreview(`data:image/jpeg;base64,${data}`);
    setLook({ photo: true });
    setError(null);
  }

  async function submit() {
    const built = countdownPayload({ title, details, date, time, timeZone, look, unit }, new Date(), existing?.createdAt);
    if (!built.ok) return setError(t(locale, ERRORS[built.error]));
    setBusy(true);
    setError(null);
    // The photo goes up when one was chosen; switching away from a photo removes the old one.
    const photoField = "photo" in look ? (photo ?? undefined) : existing?.hasPhoto ? null : undefined;
    try {
      const response = await fetch(existing ? `/api/countdowns/${existing.slug}` : "/api/countdowns", {
        method: existing ? "PUT" : "POST",
        headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ countdown: built.countdown, ...(photoField === undefined ? {} : { photo: photoField }) }),
      });
      const json = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(json.error ?? t(locale, "errGeneric"));
      if (existing) {
        window.location.href = `/c/${existing.slug}`;
      } else {
        rememberToken(json.slug, json.ownerToken);
        setToken(json.ownerToken);
        setCreated(json.slug);
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : t(locale, "errGeneric"));
      setBusy(false);
    }
  }

  async function remove() {
    if (!existing || !token || !window.confirm(t(locale, "confirmDelete"))) return;
    setBusy(true);
    const response = await fetch(`/api/countdowns/${existing.slug}`, { method: "DELETE", headers: { authorization: `Bearer ${token}` } });
    if (response.ok || response.status === 404) {
      rememberToken(existing.slug, null);
      window.location.href = "/new";
    } else {
      setBusy(false);
      setError(t(locale, "errGeneric"));
    }
  }

  // Made: off to the live page, with the chance to email an edit link first.
  if (created) {
    return (
      <Box sx={{ maxWidth: 560, mx: "auto", px: 2, py: 6 }}>
        <Typography variant="h4" component="h1" sx={{ fontFamily: `"Young Serif", Georgia, serif`, mb: 2 }}>{title}</Typography>
        <Typography sx={{ opacity: 0.8, mb: 3 }}>{t(locale, emailEnabled ? "createdNote" : "createdNoteLocal")}</Typography>
        {emailEnabled && token ? <EmailEditLink slug={created} token={token} locale={locale} /> : null}
        <Button variant="contained" size="large" href={`/c/${created}`} sx={{ mt: 3 }}>
          {t(locale, "seeItLive")} →
        </Button>
      </Box>
    );
  }

  if (existing && ready && !token) {
    return (
      <Box sx={{ maxWidth: 560, mx: "auto", px: 2, py: 6 }}>
        <Alert severity="info">{t(locale, "cantEdit")}</Alert>
        <Button href={`/c/${existing.slug}`} sx={{ mt: 2 }}>← {existing.title}</Button>
      </Box>
    );
  }

  return (
    <Box component="main" sx={{ maxWidth: 640, mx: "auto", px: 2, py: { xs: 3, sm: 5 } }}>
      <Typography variant="h4" component="h1" sx={{ fontFamily: `"Young Serif", Georgia, serif`, mb: 1 }}>
        {t(locale, existing ? "editTitle" : "newTitle")}
      </Typography>
      {existing ? null : <Typography sx={{ opacity: 0.75, mb: 3 }}>{t(locale, "newIntro")}</Typography>}

      <Box
        aria-hidden
        sx={{
          height: 180, borderRadius: 4, mb: 3, display: "flex", alignItems: "flex-end", p: 2.5, color: "#fff",
          background: `linear-gradient(180deg, rgba(10,3,6,0) 30%, rgba(10,3,6,0.75) 100%), ${backdrop}`,
        }}
      >
        <Typography sx={{ fontSize: 26, fontWeight: 700, textShadow: "0 1px 12px rgba(0,0,0,0.5)" }}>
          {title || t(locale, "titlePlaceholder")}
        </Typography>
      </Box>

      <Stack spacing={2.5}>
        <TextField label={t(locale, "fieldTitle")} placeholder={t(locale, "titlePlaceholder")} value={title}
                   onChange={(e) => setTitle(e.target.value)} slotProps={{ htmlInput: { maxLength: 120 } }} fullWidth />
        <Stack direction={{ xs: "column", sm: "row" }} spacing={2}>
          <TextField label={t(locale, "fieldDate")} type="date" value={date} onChange={(e) => setDate(e.target.value)}
                     slotProps={{ inputLabel: { shrink: true } }} fullWidth />
          <TextField label={t(locale, "fieldTime")} type="time" value={time} onChange={(e) => setTime(e.target.value)}
                     slotProps={{ inputLabel: { shrink: true } }} fullWidth />
        </Stack>
        <TextField select label={t(locale, "fieldZone")} value={timeZone} onChange={(e) => setTimeZone(e.target.value)} fullWidth>
          {(zones.includes(timeZone) ? zones : [timeZone, ...zones]).map((z) => (
            <MenuItem key={z} value={z}>{z.replaceAll("_", " ")}</MenuItem>
          ))}
        </TextField>
        <TextField label={t(locale, "fieldDetails")} placeholder={t(locale, "detailsPlaceholder")} value={details}
                   onChange={(e) => setDetails(e.target.value)} multiline minRows={2} slotProps={{ htmlInput: { maxLength: 1_000 } }} fullWidth />

        <Box>
          <Typography variant="subtitle2" sx={{ mb: 1 }}>{t(locale, "look")}</Typography>
          <Box sx={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(64px, 1fr))", gap: 1 }}>
            {WEB_SCENES.map((scene) => (
              <Swatch key={scene} label={scene} selected={"scene" in look && look.scene === scene}
                      background={`center / cover no-repeat url(/scenes/${scene}.jpg)`} onClick={() => setLook({ scene })} />
            ))}
            {WEB_GRADIENTS.map((g) => (
              <Swatch key={g.id} label={g.id} selected={"gradient" in look && look.gradient === g.id}
                      background={gradientPreview(g.stops, g.angle)} onClick={() => setLook({ gradient: g.id })} />
            ))}
          </Box>
          <Stack direction="row" spacing={1} sx={{ mt: 1.5, alignItems: "center" }}>
            <Button variant={"photo" in look ? "contained" : "outlined"} onClick={() => fileInput.current?.click()}>
              {t(locale, "choosePhoto")}
            </Button>
            <input ref={fileInput} type="file" accept="image/*" hidden onChange={(e) => choosePhoto(e.target.files?.[0])} />
          </Stack>
        </Box>

        <TextField select label={t(locale, "countIn")} value={unit} onChange={(e) => setUnit(e.target.value as Unit)} fullWidth>
          {UNITS.map(([value, key]) => <MenuItem key={value} value={value}>{t(locale, key)}</MenuItem>)}
        </TextField>

        {error ? <Alert severity="error">{error}</Alert> : null}

        <Stack direction="row" spacing={1.5} sx={{ justifyContent: "space-between", flexWrap: "wrap" }}>
          <Button variant="contained" size="large" disabled={busy || !ready} onClick={submit}>
            {t(locale, existing ? (busy ? "saving" : "saveChanges") : busy ? "creating" : "create")}
          </Button>
          {existing ? (
            <Button color="error" disabled={busy} onClick={remove}>{t(locale, "deleteCountdown")}</Button>
          ) : null}
        </Stack>

        {existing && emailEnabled && token ? <EmailEditLink slug={existing.slug} token={token} locale={locale} /> : null}
      </Stack>
    </Box>
  );
}

function Swatch({ label, selected, background, onClick }: { label: string; selected: boolean; background: string; onClick: () => void }) {
  return (
    <Box
      component="button"
      type="button"
      aria-label={label}
      aria-pressed={selected}
      onClick={onClick}
      sx={{
        aspectRatio: "1", borderRadius: 2, cursor: "pointer", background, border: "none", p: 0,
        outline: selected ? "3px solid" : "1px solid rgba(255,255,255,0.15)", outlineColor: selected ? "primary.main" : undefined,
        outlineOffset: selected ? 2 : 0,
      }}
    />
  );
}
