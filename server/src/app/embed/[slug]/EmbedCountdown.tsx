"use client";

import { useEffect, useState } from "react";
import type { PublicCountdown } from "@/lib/countdowns.ts";
import type { EmbedOptions } from "@/lib/embed.ts";
import { t, type Locale } from "@/lib/i18n.ts";
import { webStyle } from "@/lib/style.ts";
import { timeParts, viewerTarget } from "@/lib/time.ts";
import { reading } from "@/lib/units.ts";

const THEMES = {
  dark: { background: "#14070C", text: "#FAF2E3", accent: "#D91733" },
  light: { background: "#FFFFFF", text: "#1B0B10", accent: "#C3112D" },
};

/**
 * The embed itself: title, the four units, and a small link home. Sized by the iframe, so the
 * type scales with its width (vw inside an iframe is the iframe's width).
 */
export function EmbedCountdown({
  countdown,
  photoURL,
  serverNow,
  options,
  recapLine,
  liveURL,
  locale = "en",
}: {
  countdown: PublicCountdown;
  photoURL: string | null;
  serverNow: number;
  options: EmbedOptions;
  recapLine: string | null;
  liveURL: string;
  locale?: Locale;
}) {
  const [now, setNow] = useState(() => new Date(serverNow));
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  const target = countdown.floating && !mounted ? new Date(countdown.targetDate) : viewerTarget(countdown);
  const countsUp = countdown.kind === "countUp" || (options.end === "countup" && now >= target);
  const p = timeParts(now, target, countsUp);
  // In its own unit ("12 sleeps"): on the countdown's zone until the browser takes over, then the viewer's days.
  const read = reading({ ...countdown, kind: countsUp ? "countUp" : countdown.kind }, now, target, locale,
                       mounted ? undefined : countdown.timeZone);
  const style = webStyle(countdown.style, !!photoURL);
  const theme =
    options.theme === "style"
      ? {
          background: style.useImage ? `center / cover no-repeat url(${photoURL}), ${style.background}` : style.background,
          text: style.text,
          accent: style.accent,
        }
      : THEMES[options.theme];
  const finished = p.isPast;
  // At zero a hosted embed can send the page it's on somewhere: embed.js listens for this and goes
  // to the page's own data-redirect URL, so the destination is always the site owner's choice.
  const redirects = options.end === "redirect" && countdown.host === true;
  useEffect(() => {
    if (finished && redirects) window.parent.postMessage({ type: "countdowncula:zero", slug: countdown.slug }, "*");
  }, [finished, redirects, countdown.slug]);
  if (finished && options.end === "hide") return null;

  const unit = (value: number | string, label: string, pad = 2) => (
    <div key={label} style={{ textAlign: "center", minWidth: "18%" }}>
      <div style={{ fontSize: "clamp(20px, 8.5vw, 60px)", fontWeight: style.fontWeight, lineHeight: 1, fontVariantNumeric: "tabular-nums", fontFamily: style.fontFamily }}>
        {typeof value === "string" ? value : String(value).padStart(pad, "0")}
      </div>
      <div style={{ fontSize: "clamp(10px, 2.6vw, 14px)", opacity: 0.75, marginTop: 4, letterSpacing: 0.5 }}>{label}</div>
    </div>
  );

  return (
    <a
      href={liveURL}
      target="_blank"
      rel="noopener"
      style={{
        position: "fixed", inset: 0, display: "flex", flexDirection: "column", justifyContent: "space-evenly", gap: "1.5vw",
        padding: "3vw 4.5vw", borderRadius: 16, overflow: "hidden", textDecoration: "none",
        background: theme.background, color: theme.text, fontFamily: `"Instrument Sans", system-ui, sans-serif`,
        boxShadow: options.theme === "style" && style.lightText ? "inset 0 -120px 120px -40px rgba(10,3,6,0.75)" : undefined,
      }}
    >
      <div className="embed-title" style={{ fontSize: "clamp(13px, 4vw, 26px)", fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", fontFamily: style.fontFamily }}>
        {countdown.title}
      </div>
      {finished && options.end !== "countup" ? (
        <div style={{ fontSize: "clamp(22px, 9vw, 56px)", fontWeight: 700, lineHeight: 1.05, fontFamily: style.fontFamily }}>
          {options.end === "recap" ? t(locale, "itHappened") : options.message === "It's here!" ? t(locale, "itsHere") : options.message}
          {options.end === "recap" && recapLine ? (
            <div style={{ fontSize: "clamp(12px, 3.4vw, 20px)", fontWeight: 500, opacity: 0.85, marginTop: 6 }}>{recapLine}</div>
          ) : null}
        </div>
      ) : (
        <div style={{ display: "flex", justifyContent: read ? "space-evenly" : "space-between", gap: "2vw" }} suppressHydrationWarning>
          {read ? read.tiles.map((tile) => unit(tile.value, tile.label)) : [
            unit(p.days, t(locale, "days"), 1),
            unit(p.hours, t(locale, "hours")),
            unit(p.minutes, t(locale, "min")),
            unit(p.seconds, t(locale, "sec")),
          ]}
        </div>
      )}
      {countdown.host ? null : (
        <div className="embed-credit" style={{ fontSize: "clamp(10px, 2.4vw, 13px)", opacity: 0.7, textAlign: "right" }}>
          {t(locale, "madeWith")} <span style={{ color: theme.accent, fontWeight: 700 }}>Count Downcula</span>
        </div>
      )}
    </a>
  );
}
