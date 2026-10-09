"use client";

import { useEffect, useRef, useState } from "react";
import type { PublicCountdown } from "@/lib/countdowns.ts";
import { t, type Locale } from "@/lib/i18n.ts";
import { presentPhase } from "@/lib/present.ts";
import { webStyle } from "@/lib/style.ts";
import { timeParts, viewerTarget } from "@/lib/time.ts";
import { reading } from "@/lib/units.ts";

const pad = (n: number) => String(n).padStart(2, "0");

/**
 * The countdown full screen for a room: huge digits in the countdown's style, the last ten seconds
 * as one number, confetti at zero, and a QR code so people can join from their phones. Keeps the
 * screen awake while it's open.
 */
export function Present({
  countdown,
  photoURL,
  serverNow,
  qr,
  locale,
}: {
  countdown: PublicCountdown;
  photoURL: string | null;
  serverNow: number;
  /** The room link's QR code, drawn on the server. */
  qr: { size: number; path: string };
  locale: Locale;
}) {
  const [now, setNow] = useState(() => new Date(serverNow));
  const [mounted, setMounted] = useState(false);
  const [idle, setIdle] = useState(false);
  const [fullScreen, setFullScreen] = useState(false);
  const sentZero = useRef(false);

  // A quarter-second tick, so each of the last ten seconds lands on time.
  useEffect(() => {
    setMounted(true);
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 250);
    return () => clearInterval(id);
  }, []);

  // Keep the screen on. Browsers drop the lock when the tab is hidden, so take it again on return.
  useEffect(() => {
    let lock: { release: () => Promise<void> } | null = null;
    const take = async () => {
      try {
        lock = await (navigator as Navigator & { wakeLock?: { request: (t: "screen") => Promise<{ release: () => Promise<void> }> } })
          .wakeLock?.request("screen") ?? null;
      } catch {}
    };
    const onVisible = () => { if (document.visibilityState === "visible") take(); };
    take();
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      document.removeEventListener("visibilitychange", onVisible);
      lock?.release().catch(() => {});
    };
  }, []);

  // The cursor and the full screen button get out of the way after a few still seconds.
  useEffect(() => {
    let timer = setTimeout(() => setIdle(true), 3000);
    const wake = () => {
      setIdle(false);
      clearTimeout(timer);
      timer = setTimeout(() => setIdle(true), 3000);
    };
    const onKey = (e: KeyboardEvent) => {
      wake();
      if (e.key === "f" || e.key === "F") toggleFullScreen();
    };
    const onFull = () => setFullScreen(!!document.fullscreenElement);
    window.addEventListener("mousemove", wake);
    window.addEventListener("keydown", onKey);
    document.addEventListener("fullscreenchange", onFull);
    return () => {
      clearTimeout(timer);
      window.removeEventListener("mousemove", wake);
      window.removeEventListener("keydown", onKey);
      document.removeEventListener("fullscreenchange", onFull);
    };
  }, []);

  const target = countdown.floating && !mounted ? new Date(countdown.targetDate) : viewerTarget(countdown);
  const countsUp = countdown.kind === "countUp";
  const p = timeParts(now, target, countsUp);
  const { phase, finalSecond } = presentPhase(now, target, countsUp);
  const read = reading(countdown, now, target, locale, mounted ? undefined : countdown.timeZone);
  const style = webStyle(countdown.style, !!photoURL);

  // Count the rooms still watching at zero. Once per page, and only for a page that was open before it.
  useEffect(() => {
    if (phase !== "zero" || sentZero.current || !mounted) return;
    sentZero.current = true;
    if (now.getTime() - target.getTime() < 60_000) navigator.sendBeacon?.(`/c/${countdown.slug}/present/zero`);
  }, [phase, mounted, now, target, countdown.slug]);

  const tiles: { value: string; label: string }[] = read
    ? read.tiles
    : p.days > 0
      ? [
          { value: String(p.days), label: t(locale, "days") },
          { value: pad(p.hours), label: t(locale, "hours") },
          { value: pad(p.minutes), label: t(locale, "min") },
          { value: pad(p.seconds), label: t(locale, "sec") },
        ]
      : [
          ...(p.hours > 0 ? [{ value: pad(p.hours), label: t(locale, "hours") }] : []),
          { value: pad(p.minutes), label: t(locale, "min") },
          { value: pad(p.seconds), label: t(locale, "sec") },
        ];

  return (
    <main
      style={{
        position: "fixed", inset: 0, overflow: "hidden", display: "flex", flexDirection: "column",
        alignItems: "center", justifyContent: "center", textAlign: "center",
        background: style.useImage ? `center / cover no-repeat url(${photoURL}), ${style.background}` : style.background,
        color: style.text, fontFamily: style.fontFamily, cursor: idle ? "none" : "default",
      }}
    >
      <style>{`
        @keyframes present-beat { from { transform: scale(1.25); opacity: 0.4 } to { transform: scale(1); opacity: 1 } }
        @keyframes present-fall { to { transform: translateY(110vh) rotate(720deg) } }
      `}</style>
      <div
        aria-hidden
        style={{
          position: "absolute", inset: 0,
          background: style.lightText
            ? "radial-gradient(ellipse at center, rgba(10,3,6,0.35) 0%, rgba(10,3,6,0.7) 100%)"
            : "radial-gradient(ellipse at center, rgba(255,255,255,0.2) 0%, rgba(255,255,255,0.65) 100%)",
        }}
      />
      <div style={{ position: "relative", width: "100%", padding: "0 4vw" }} suppressHydrationWarning>
        <h1 style={{ fontWeight: style.fontWeight, fontSize: "clamp(28px, 6vw, 96px)", lineHeight: 1.05, margin: "0 0 4vh" }}>
          {countdown.title}
        </h1>
        {phase === "zero" ? (
          <div style={{ fontWeight: style.fontWeight, fontSize: "clamp(64px, 16vw, 260px)", lineHeight: 1, animation: "present-beat 0.6s ease-out" }}>
            {t(locale, "itsHere")}
          </div>
        ) : phase === "final" ? (
          <div
            key={finalSecond}
            style={{
              fontWeight: style.fontWeight, fontSize: "clamp(160px, 42vh, 520px)", lineHeight: 1, color: style.accent,
              fontVariantNumeric: "tabular-nums", animation: "present-beat 0.9s ease-out",
            }}
          >
            {finalSecond}
          </div>
        ) : (
          <div style={{ display: "flex", justifyContent: "center", gap: "4vw" }}>
            {tiles.map((tile) => (
              <div key={tile.label} style={{ minWidth: "12vw" }}>
                <div style={{ fontWeight: style.fontWeight, fontSize: `clamp(56px, ${tiles.length > 2 ? 13 : 20}vw, 340px)`, lineHeight: 1, fontVariantNumeric: "tabular-nums" }}>
                  {tile.value}
                </div>
                <div style={{ fontSize: "clamp(14px, 2vw, 34px)", opacity: 0.75, marginTop: "1.5vh", letterSpacing: 1, fontFamily: `"Instrument Sans", system-ui, sans-serif` }}>
                  {tile.label}
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      {phase === "zero" ? <Confetti accent={style.accent} /> : null}

      <figure
        style={{
          position: "absolute", right: "2.5vw", bottom: "3vh", margin: 0, display: "flex", alignItems: "center", gap: 14,
          padding: 12, borderRadius: 16, background: "rgba(255,255,255,0.92)", color: "#1a0a0f",
          fontFamily: `"Instrument Sans", system-ui, sans-serif`,
        }}
      >
        <svg viewBox={`0 0 ${qr.size} ${qr.size}`} style={{ width: "clamp(84px, 11vh, 160px)", height: "auto", display: "block" }} role="img" aria-label={t(locale, "presentScan")}>
          <rect width={qr.size} height={qr.size} fill="#fff" />
          <path d={qr.path} fill="#000" shapeRendering="crispEdges" />
        </svg>
        <figcaption style={{ maxWidth: 160, fontSize: "clamp(13px, 1.6vh, 20px)", fontWeight: 600, textAlign: "left", lineHeight: 1.25 }}>
          {t(locale, "presentScan")}
          {countdown.host ? null : <div style={{ fontWeight: 500, opacity: 0.6, marginTop: 4 }}>Count Downcula</div>}
        </figcaption>
      </figure>

      <button
        onClick={toggleFullScreen}
        style={{
          position: "absolute", top: "3vh", right: "2.5vw", padding: "10px 16px", borderRadius: 999,
          border: "1px solid currentColor", background: "transparent", color: "inherit", font: "600 15px system-ui, sans-serif",
          opacity: idle ? 0 : 0.8, transition: "opacity 0.4s", cursor: "pointer",
        }}
      >
        {t(locale, fullScreen ? "exitFullScreen" : "fullScreen")}
      </button>
    </main>
  );
}

function toggleFullScreen() {
  if (document.fullscreenElement) document.exitFullscreen().catch(() => {});
  else document.documentElement.requestFullscreen?.().catch(() => {});
}

/** Confetti at zero: CSS-animated pieces from a fixed seed, so it needs no library. */
function Confetti({ accent }: { accent: string }) {
  const colors = ["#FF4D6D", "#FFD166", "#06D6A0", "#118AB2", "#C77DFF", "#FFFFFF", accent, accent];
  let seed = 0xc0ffee;
  const rand = () => ((seed = (seed * 1_103_515_245 + 12_345) % 2_147_483_648) / 2_147_483_648);
  const pieces = Array.from({ length: 160 }, (_, i) => ({
    left: rand() * 100, delay: rand() * 2.5, duration: 3 + rand() * 3, size: 8 + rand() * 10,
    color: colors[i % colors.length], tilt: rand() * 360,
  }));
  return (
    <div aria-hidden style={{ position: "absolute", inset: 0, pointerEvents: "none", overflow: "hidden" }}>
      {pieces.map((c, i) => (
        <span
          key={i}
          style={{
            position: "absolute", top: "-5vh", left: `${c.left}%`, width: c.size, height: c.size * 0.45, background: c.color,
            transform: `rotate(${c.tilt}deg)`, animation: `present-fall ${c.duration}s linear ${c.delay}s 3 both`,
          }}
        />
      ))}
    </div>
  );
}
