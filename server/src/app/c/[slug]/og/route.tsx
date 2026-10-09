import { readFile } from "node:fs/promises";
import path from "node:path";
import { ImageResponse } from "next/og";
import { getCountdown, getPhoto } from "@/lib/countdowns.ts";
import { backdropSrc } from "@/lib/backdrop.ts";
import { loadRecap, recapText } from "@/lib/recap.ts";
import { webStyle } from "@/lib/style.ts";
import { dialRemaining, headline } from "@/lib/time.ts";
import { isSlug } from "@/lib/validate.ts";

const fontsDir = path.join(process.cwd(), "assets", "fonts");
const assets = Promise.all([
  readFile(path.join(fontsDir, "young-serif-400.woff")),
  readFile(path.join(fontsDir, "instrument-sans-latin-500-normal.woff")),
  readFile(path.join(fontsDir, "instrument-sans-latin-700-normal.woff")),
  readFile(path.join(process.cwd(), "assets", "app-icon.png")),
]);

const WIDTH = 1200;
const HEIGHT = 630;

/** The link preview: renders on request so it always shows today's number. */
export async function GET(_request: Request, { params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const doc = isSlug(slug) ? await getCountdown(slug) : null;
  if (!doc) return new Response("Not found", { status: 404 });

  const [serif, sans500, sans700, icon] = await assets;
  const photo = doc.hasPhoto ? await getPhoto(slug) : null;
  const style = webStyle(doc.style, !!photo);
  const backdrop = await backdropSrc(style, photo);
  const now = new Date();
  const live = headline(now, doc.targetDate, doc.kind, doc.timeZone);
  // After zero: "It happened." and who was there, instead of a date that's passed.
  const recap = doc.kind === "countUp" ? null : await loadRecap(doc, now);
  const words = recap ? recapText(recap, doc.visibility === "public") : null;
  const value = words ? "It happened." : live.value;
  const caption = words ? (words.together ?? words.counted ?? live.caption) : live.caption;
  const remaining = dialRemaining(now, doc.createdAt, doc.targetDate, doc.kind);
  const serifNumbers = (doc.style as { font?: string }).font === "serif";

  const ring = 300;
  const stroke = 26;
  const radius = (ring - stroke) / 2;
  const circumference = 2 * Math.PI * radius;

  const image = new ImageResponse(
    (
      <div
        style={{
          width: WIDTH,
          height: HEIGHT,
          display: "flex",
          position: "relative",
          background: style.baseBackground,
          color: style.text,
          fontFamily: "Instrument Sans",
        }}
      >
        {backdrop ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img
            src={backdrop}
            width={WIDTH}
            height={HEIGHT}
            style={{ position: "absolute", inset: 0, objectFit: "cover" }}
          />
        ) : null}
        <div
          style={{
            position: "absolute",
            inset: 0,
            display: "flex",
            background: style.lightText
              ? "linear-gradient(90deg, rgba(10,3,6,0.82) 0%, rgba(10,3,6,0.55) 55%, rgba(10,3,6,0.15) 100%)"
              : "linear-gradient(90deg, rgba(255,255,255,0.8) 0%, rgba(255,255,255,0.5) 55%, rgba(255,255,255,0.1) 100%)",
          }}
        />
        <div style={{ position: "relative", display: "flex", width: "100%", padding: "64px 72px", alignItems: "center" }}>
          <div style={{ display: "flex", flexDirection: "column", flex: 1, paddingRight: 40 }}>
            <div style={{ display: "flex", fontSize: 44, fontWeight: 500, lineHeight: 1.15, maxHeight: 108, overflow: "hidden" }}>
              {doc.title}
            </div>
            <div
              style={{
                display: "flex",
                fontFamily: serifNumbers ? "Young Serif" : "Instrument Sans",
                fontWeight: 700,
                fontSize: value.length > 9 ? 112 : 140,
                lineHeight: 1,
                marginTop: 18,
                letterSpacing: -2,
              }}
            >
              {value}
            </div>
            <div style={{ display: "flex", fontSize: 34, fontWeight: 500, opacity: 0.85, marginTop: 14 }}>{caption}</div>
            <div style={{ display: "flex", alignItems: "center", marginTop: 48, fontSize: 26, fontWeight: 700, opacity: 0.85 }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={`data:image/png;base64,${icon.toString("base64")}`} width={44} height={44} style={{ borderRadius: 10, marginRight: 14 }} />
              Count Downcula
            </div>
          </div>
          <svg width={ring} height={ring} viewBox={`0 0 ${ring} ${ring}`}>
            <circle cx={ring / 2} cy={ring / 2} r={radius} fill="none" stroke="rgba(255,255,255,0.18)" strokeWidth={stroke} />
            <circle
              cx={ring / 2}
              cy={ring / 2}
              r={radius}
              fill="none"
              stroke={style.accent}
              strokeWidth={stroke}
              strokeLinecap="round"
              strokeDasharray={`${circumference * Math.max(remaining, 0.001)} ${circumference}`}
              transform={`rotate(-90 ${ring / 2} ${ring / 2})`}
            />
          </svg>
        </div>
      </div>
    ),
    {
      width: WIDTH,
      height: HEIGHT,
      fonts: [
        { name: "Young Serif", data: serif, weight: 400, style: "normal" },
        { name: "Instrument Sans", data: sans500, weight: 500, style: "normal" },
        { name: "Instrument Sans", data: sans700, weight: 700, style: "normal" },
      ],
    },
  );
  // Fresh within the hour. The page also changes the image URL each day, for apps that cache by URL.
  image.headers.set("Cache-Control", "public, max-age=600, s-maxage=3600, stale-while-revalidate=600");
  return image;
}
