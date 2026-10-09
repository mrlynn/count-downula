"use client";

import { Box, Button, Dialog, DialogActions, DialogContent, DialogTitle, Menu, MenuItem, Stack, TextField, Typography } from "@mui/material";
import { useEffect, useState } from "react";
import { calendarLinks } from "@/lib/calendar.ts";
import type { PublicCountdown } from "@/lib/countdowns.ts";
import { embeddable, embedSnippet } from "@/lib/embed.ts";
import { t, type Locale } from "@/lib/i18n.ts";
import { recapText, type Recap } from "@/lib/recapText.ts";
import { webStyle } from "@/lib/style.ts";
import { dialRemaining, timeParts, viewerTarget } from "@/lib/time.ts";
import CoffinPanel from "./CoffinPanel.tsx";
import PoolPanel from "./PoolPanel.tsx";

const DOWNLOAD = "https://www.countdowncula.com";

function Dial({ remaining, accent }: { remaining: number; accent: string }) {
  const size = 120;
  const stroke = 11;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="rgba(255,255,255,0.18)" strokeWidth={stroke} />
      <circle
        cx={size / 2}
        cy={size / 2}
        r={r}
        fill="none"
        stroke={accent}
        strokeWidth={stroke}
        strokeLinecap="round"
        strokeDasharray={`${c * Math.max(remaining, 0.001)} ${c}`}
        transform={`rotate(-90 ${size / 2} ${size / 2})`}
        style={{ transition: "stroke-dasharray 1s linear" }}
      />
    </svg>
  );
}

function Unit({ value, label, pad = 2, fontFamily, fontWeight }: { value: number; label: string; pad?: number; fontFamily: string; fontWeight: number }) {
  return (
    <Box sx={{ minWidth: { xs: 64, sm: 96 }, textAlign: "center" }}>
      <Typography
        component="div"
        sx={{ fontFamily, fontWeight, fontSize: { xs: 44, sm: 72 }, lineHeight: 1, fontVariantNumeric: "tabular-nums" }}
      >
        {String(value).padStart(pad, "0")}
      </Typography>
      <Typography sx={{ fontSize: { xs: 13, sm: 15 }, opacity: 0.75, mt: 0.75, letterSpacing: 0.5 }}>{label}</Typography>
    </Box>
  );
}

export function LiveCountdown({
  countdown,
  photoURL,
  serverNow,
  memberCount,
  sealed = 0,
  walletURL = null,
  recap = null,
  calendarURL = null,
  locale = "en",
}: {
  countdown: PublicCountdown;
  photoURL: string | null;
  serverNow: number;
  memberCount: number;
  /** Notes and photos waiting in the coffin, before zero. */
  sealed?: number;
  /** Where to get the Apple Wallet pass, once passes are set up. */
  walletURL?: string | null;
  /** After zero: how long it was counted, who counted, what the coffin held, who guessed closest. */
  recap?: Recap | null;
  /** The countdown's calendar feed, for Add to Calendar. */
  calendarURL?: string | null;
  /** The viewer's language, from Accept-Language. */
  locale?: Locale;
}) {
  const [calendarMenu, setCalendarMenu] = useState<HTMLElement | null>(null);
  const [embedOpen, setEmbedOpen] = useState(false);
  const [copied, setCopied] = useState(false);

  // Start from the server's clock so the first client render matches the HTML, then tick locally.
  const [now, setNow] = useState(() => new Date(serverNow));
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  const snippet = mounted ? embedSnippet(window.location.origin, countdown.slug) : "";
  // Floating times only become real on the viewer's clock, so wait for the browser before using one.
  const target = countdown.floating && !mounted ? new Date(countdown.targetDate) : viewerTarget(countdown);
  const created = new Date(countdown.createdAt);
  const countsUp = countdown.kind === "countUp";
  const p = timeParts(now, target, countsUp);
  // Floating times pass at each viewer's own midnight, so the recap waits for this viewer's zero too.
  const words = recap && p.isPast ? recapText(recap, !!countdown.isPublic, locale) : null;
  // Kept counting up after zero: still say how many counted down to it.
  const together = recap && countsUp ? recapText(recap, !!countdown.isPublic, locale).together : null;
  const style = webStyle(countdown.style, !!photoURL);
  const dateLine = mounted
    ? target.toLocaleString(undefined, { weekday: "long", month: "long", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" })
    : "";

  return (
    <Box component="main" sx={{ minHeight: "100dvh", display: "flex", flexDirection: "column" }}>
      <Box
        sx={{
          position: "relative",
          flex: 1,
          minHeight: { xs: "78dvh", sm: "72dvh" },
          display: "flex",
          alignItems: "flex-end",
          background: style.useImage ? `center / cover no-repeat url(${photoURL}), ${style.background}` : style.background,
          color: style.text,
        }}
      >
        <Box
          sx={{
            position: "absolute",
            inset: 0,
            background: style.lightText
              ? "linear-gradient(180deg, rgba(10,3,6,0.15) 0%, rgba(10,3,6,0.35) 45%, rgba(10,3,6,0.88) 100%)"
              : "linear-gradient(180deg, rgba(255,255,255,0.1) 0%, rgba(255,255,255,0.75) 100%)",
          }}
        />
        <Box sx={{ position: "absolute", top: { xs: 20, sm: 32 }, right: { xs: 16, sm: 32 } }}>
          <Dial remaining={dialRemaining(now, created, target, countdown.kind)} accent={style.accent} />
        </Box>
        {/* A second scrim sized to the text, so busy backdrops (stripes, a bright sun) stay behind it
            however tall the hero or the text block is. */}
        <Box
          sx={{
            position: "relative",
            width: "100%",
            pt: { xs: 12, sm: 16 },
            background: style.lightText
              ? "linear-gradient(180deg, rgba(10,3,6,0) 0%, rgba(10,3,6,0.72) 34%, rgba(10,3,6,0.86) 100%)"
              : "linear-gradient(180deg, rgba(255,255,255,0) 0%, rgba(255,255,255,0.72) 34%, rgba(255,255,255,0.86) 100%)",
            textShadow: style.lightText ? "0 1px 14px rgba(0,0,0,0.45)" : "0 1px 14px rgba(255,255,255,0.5)",
          }}
        >
        <Box sx={{ width: "100%", maxWidth: 960, mx: "auto", px: { xs: 2, sm: 4 }, pb: { xs: 4, sm: 6 } }}>
          <Typography
            variant="h1"
            sx={{ fontFamily: style.fontFamily, fontWeight: style.fontWeight, fontSize: { xs: 34, sm: 52 }, lineHeight: 1.1, mb: 1 }}
          >
            {countdown.title}
          </Typography>
          <Typography sx={{ opacity: 0.85, minHeight: "1.5em", mb: 3 }} suppressHydrationWarning>
            {p.isPast
              ? words ? dateLine : t(locale, "itsHereOn", { date: dateLine })
              : countsUp
                ? t(locale, "since", { date: dateLine })
                : countdown.pool && !countdown.pool.answer
                  ? t(locale, "expected", { date: dateLine })
                  : dateLine}
          </Typography>
          {words ? (
            <Box>
              <Typography
                component="div"
                sx={{ fontFamily: style.fontFamily, fontWeight: style.fontWeight, fontSize: { xs: 52, sm: 84 }, lineHeight: 1 }}
              >
                {t(locale, "itHappened")}
              </Typography>
              {words.counted ? (
                <Typography sx={{ fontSize: { xs: 22, sm: 28 }, fontWeight: 600, mt: 1.5 }}>{words.counted}</Typography>
              ) : null}
              {words.people ? <Typography sx={{ fontSize: { xs: 17, sm: 20 }, opacity: 0.85, mt: 1 }}>{words.people}</Typography> : null}
            </Box>
          ) : (
            <Stack direction="row" spacing={{ xs: 1, sm: 3 }} sx={{ flexWrap: "wrap" }} aria-live="off">
              <Unit value={p.days} label={t(locale, "days")} pad={1} fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
              <Unit value={p.hours} label={t(locale, "hours")} fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
              <Unit value={p.minutes} label={t(locale, "min")} fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
              <Unit value={p.seconds} label={t(locale, "sec")} fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
            </Stack>
          )}
          {countdown.details ? (
            <Typography sx={{ mt: 3, maxWidth: 640, opacity: 0.9, whiteSpace: "pre-wrap" }}>{countdown.details}</Typography>
          ) : null}
          {together ? (
            <Typography sx={{ mt: 2, opacity: 0.8, fontWeight: 600 }}>{together}</Typography>
          ) : null}
          {memberCount > 0 && !words && !together ? (
            <Typography sx={{ mt: 2, opacity: 0.8, fontWeight: 600 }}>
              {t(locale, "countingDown", { n: memberCount })}
            </Typography>
          ) : null}
        </Box>
        </Box>
      </Box>
      {countdown.pool ? <PoolPanel slug={countdown.slug} estimate={countdown.targetDate} locale={locale} /> : null}
      {/* Link-shared countdowns only: public crypt entries and plain count-ups have no coffin. */}
      {!countdown.isPublic && (countdown.kind !== "countUp" || countdown.keptCounting) ? (
        <CoffinPanel slug={countdown.slug} opensAt={countdown.targetDate} initialSealed={sealed || recap?.notes || 0}
                     maxPhotos={countdown.host ? 4 : 1} locale={locale} />
      ) : null}
      <Box sx={{ bgcolor: "background.default", px: { xs: 2, sm: 4 }, py: { xs: 4, sm: 5 } }}>
        <Stack
          direction={{ xs: "column", md: "row" }}
          spacing={2}
          sx={{ maxWidth: 960, mx: "auto", alignItems: { xs: "stretch", md: "center" }, justifyContent: "space-between" }}
        >
          {/* A hosted page is the host's: no Count Downcula pitch. */}
          {countdown.host ? <Box /> : (
            <Box>
              <Typography sx={{ fontFamily: `"Young Serif", Georgia, serif`, fontSize: 22 }}>Count Downcula</Typography>
              <Typography sx={{ opacity: 0.7 }}>
                {t(locale, words ? "pitchAfter" : "pitchBefore")}
              </Typography>
            </Box>
          )}
          <Stack direction={{ xs: "column", sm: "row" }} sx={{ gap: 1.5, flexWrap: "wrap", "& .MuiButton-root": { whiteSpace: "nowrap" } }}>
            {/* Same-site links don't open the app, so this uses the app's own scheme. */}
            {words ? null : (
              <Button variant="contained" size="large" href={`countdownula://join/${countdown.slug}`}>
                {t(locale, "countDownWithMe")}
              </Button>
            )}
            {calendarURL && !words ? (
              <>
                <Button variant="outlined" size="large" onClick={(e) => setCalendarMenu(e.currentTarget)}>
                  {t(locale, "addToCalendar")}
                </Button>
                <Menu anchorEl={calendarMenu} open={Boolean(calendarMenu)} onClose={() => setCalendarMenu(null)}>
                  {/* Subscriptions, so the event moves if the date does. */}
                  <MenuItem component="a" href={calendarLinks(calendarURL).webcal} onClick={() => setCalendarMenu(null)}>
                    {t(locale, "appleOutlook")}
                  </MenuItem>
                  <MenuItem component="a" href={calendarLinks(calendarURL).google} target="_blank" rel="noopener" onClick={() => setCalendarMenu(null)}>
                    {t(locale, "googleCalendar")}
                  </MenuItem>
                  <MenuItem component="a" href={calendarURL} download onClick={() => setCalendarMenu(null)}>
                    {t(locale, "downloadIcs")}
                  </MenuItem>
                </Menu>
              </>
            ) : null}
            {walletURL && !words ? (
              <Button variant="outlined" size="large" href={walletURL}>
                {t(locale, "addToWallet")}
              </Button>
            ) : null}
            {countdown.host ? null : (
              <Button variant={words ? "contained" : "outlined"} size="large" href={DOWNLOAD}>
                {t(locale, "getTheApp")}
              </Button>
            )}
          </Stack>
        </Stack>
        {embeddable(countdown) ? (
          <Box sx={{ maxWidth: 960, mx: "auto", mt: 3 }}>
            <Button size="small" color="inherit" sx={{ opacity: 0.7 }} onClick={() => setEmbedOpen(true)}>
              {t(locale, "embedOnSite")}
            </Button>
          </Box>
        ) : null}
      </Box>
      <Dialog open={embedOpen} onClose={() => setEmbedOpen(false)} fullWidth maxWidth="sm">
        <DialogTitle>{t(locale, "embedTitle")}</DialogTitle>
        <DialogContent>
          <Typography sx={{ opacity: 0.8, mb: 2 }}>
            {t(locale, "embedBody")}
          </Typography>
          <TextField value={snippet} fullWidth multiline slotProps={{ input: { readOnly: true, sx: { fontFamily: "ui-monospace, monospace", fontSize: 13 } } }} />
          <Typography variant="body2" sx={{ opacity: 0.7, mt: 2 }}>
            {t(locale, "embedOptions")}
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button
            onClick={() => {
              navigator.clipboard?.writeText(snippet).then(() => setCopied(true)).catch(() => {});
            }}
          >
            {t(locale, copied ? "copied" : "copy")}
          </Button>
          <Button onClick={() => setEmbedOpen(false)}>{t(locale, "done")}</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
