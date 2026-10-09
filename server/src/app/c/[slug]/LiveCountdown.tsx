"use client";

import { Box, Button, Dialog, DialogActions, DialogContent, DialogTitle, Menu, MenuItem, Stack, TextField, Typography } from "@mui/material";
import { useEffect, useState } from "react";
import { calendarLinks } from "@/lib/calendar.ts";
import type { PublicCountdown } from "@/lib/countdowns.ts";
import { embeddable, embedSnippet } from "@/lib/embed.ts";
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

function Unit({ value, label, fontFamily, fontWeight }: { value: number; label: string; fontFamily: string; fontWeight: number }) {
  return (
    <Box sx={{ minWidth: { xs: 64, sm: 96 }, textAlign: "center" }}>
      <Typography
        component="div"
        sx={{ fontFamily, fontWeight, fontSize: { xs: 44, sm: 72 }, lineHeight: 1, fontVariantNumeric: "tabular-nums" }}
      >
        {String(value).padStart(label === "days" ? 1 : 2, "0")}
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
  const words = recap && p.isPast ? recapText(recap, !!countdown.isPublic) : null;
  // Kept counting up after zero: still say how many counted down to it.
  const together = recap && countsUp ? recapText(recap, !!countdown.isPublic).together : null;
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
              ? words ? dateLine : `It's here! ${dateLine}`
              : countsUp
                ? `Since ${dateLine}`
                : countdown.pool && !countdown.pool.answer
                  ? `Expected ${dateLine}`
                  : dateLine}
          </Typography>
          {words ? (
            <Box>
              <Typography
                component="div"
                sx={{ fontFamily: style.fontFamily, fontWeight: style.fontWeight, fontSize: { xs: 52, sm: 84 }, lineHeight: 1 }}
              >
                It happened.
              </Typography>
              {words.counted ? (
                <Typography sx={{ fontSize: { xs: 22, sm: 28 }, fontWeight: 600, mt: 1.5 }}>{words.counted}</Typography>
              ) : null}
              {words.people ? <Typography sx={{ fontSize: { xs: 17, sm: 20 }, opacity: 0.85, mt: 1 }}>{words.people}</Typography> : null}
            </Box>
          ) : (
            <Stack direction="row" spacing={{ xs: 1, sm: 3 }} sx={{ flexWrap: "wrap" }} aria-live="off">
              <Unit value={p.days} label="days" fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
              <Unit value={p.hours} label="hours" fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
              <Unit value={p.minutes} label="min" fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
              <Unit value={p.seconds} label="sec" fontFamily={style.fontFamily} fontWeight={style.fontWeight} />
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
              {memberCount === 1 ? "1 person is counting down" : `${memberCount.toLocaleString()} people are counting down`}
            </Typography>
          ) : null}
        </Box>
        </Box>
      </Box>
      {countdown.pool ? <PoolPanel slug={countdown.slug} estimate={countdown.targetDate} /> : null}
      {/* Link-shared countdowns only: public crypt entries and plain count-ups have no coffin. */}
      {!countdown.isPublic && (countdown.kind !== "countUp" || countdown.keptCounting) ? (
        <CoffinPanel slug={countdown.slug} opensAt={countdown.targetDate} initialSealed={sealed || recap?.notes || 0} />
      ) : null}
      <Box sx={{ bgcolor: "background.default", px: { xs: 2, sm: 4 }, py: { xs: 4, sm: 5 } }}>
        <Stack
          direction={{ xs: "column", md: "row" }}
          spacing={2}
          sx={{ maxWidth: 960, mx: "auto", alignItems: { xs: "stretch", md: "center" }, justifyContent: "space-between" }}
        >
          <Box>
            <Typography sx={{ fontFamily: `"Young Serif", Georgia, serif`, fontSize: 22 }}>Count Downcula</Typography>
            <Typography sx={{ opacity: 0.7 }}>
              {words
                ? "Count down to your next big day together: it shows up on your Lock Screen, watch and menu bar."
                : "Count down together: it shows up on your Lock Screen, watch and menu bar, and stays in step when it changes."}
            </Typography>
          </Box>
          <Stack direction={{ xs: "column", sm: "row" }} sx={{ gap: 1.5, flexWrap: "wrap", "& .MuiButton-root": { whiteSpace: "nowrap" } }}>
            {/* Same-site links don't open the app, so this uses the app's own scheme. */}
            {words ? null : (
              <Button variant="contained" size="large" href={`countdownula://join/${countdown.slug}`}>
                Count down with me
              </Button>
            )}
            {calendarURL && !words ? (
              <>
                <Button variant="outlined" size="large" onClick={(e) => setCalendarMenu(e.currentTarget)}>
                  Add to Calendar
                </Button>
                <Menu anchorEl={calendarMenu} open={Boolean(calendarMenu)} onClose={() => setCalendarMenu(null)}>
                  {/* Subscriptions, so the event moves if the date does. */}
                  <MenuItem component="a" href={calendarLinks(calendarURL).webcal} onClick={() => setCalendarMenu(null)}>
                    Apple or Outlook Calendar
                  </MenuItem>
                  <MenuItem component="a" href={calendarLinks(calendarURL).google} target="_blank" rel="noopener" onClick={() => setCalendarMenu(null)}>
                    Google Calendar
                  </MenuItem>
                  <MenuItem component="a" href={calendarURL} download onClick={() => setCalendarMenu(null)}>
                    Download .ics
                  </MenuItem>
                </Menu>
              </>
            ) : null}
            {walletURL && !words ? (
              <Button variant="outlined" size="large" href={walletURL}>
                Add to Apple Wallet
              </Button>
            ) : null}
            <Button variant={words ? "contained" : "outlined"} size="large" href={DOWNLOAD}>
              Get the app
            </Button>
          </Stack>
        </Stack>
        {embeddable(countdown) ? (
          <Box sx={{ maxWidth: 960, mx: "auto", mt: 3 }}>
            <Button size="small" color="inherit" sx={{ opacity: 0.7 }} onClick={() => setEmbedOpen(true)}>
              Embed on your site
            </Button>
          </Box>
        ) : null}
      </Box>
      <Dialog open={embedOpen} onClose={() => setEmbedOpen(false)} fullWidth maxWidth="sm">
        <DialogTitle>Embed this countdown</DialogTitle>
        <DialogContent>
          <Typography sx={{ opacity: 0.8, mb: 2 }}>
            Paste this where the countdown should go. It ticks live and stays in step with the owner&apos;s edits.
          </Typography>
          <TextField value={snippet} fullWidth multiline slotProps={{ input: { readOnly: true, sx: { fontFamily: "ui-monospace, monospace", fontSize: 13 } } }} />
          <Typography variant="body2" sx={{ opacity: 0.7, mt: 2 }}>
            Options: data-theme=&quot;dark&quot; or &quot;light&quot; instead of the countdown&apos;s own look, and data-end=&quot;recap&quot;,
            &quot;countup&quot; or &quot;hide&quot; for what shows at zero (or data-message=&quot;Doors are open!&quot;).
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button
            onClick={() => {
              navigator.clipboard?.writeText(snippet).then(() => setCopied(true)).catch(() => {});
            }}
          >
            {copied ? "Copied" : "Copy"}
          </Button>
          <Button onClick={() => setEmbedOpen(false)}>Done</Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
}
