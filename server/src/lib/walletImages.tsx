// The images a pass needs, drawn with the same renderer as the link preview.
import { readFile } from "node:fs/promises";
import path from "node:path";
import { ImageResponse } from "next/og";
import { webStyle } from "./style.ts";

const assets = Promise.all([
  readFile(path.join(process.cwd(), "assets", "app-icon.png")),
  readFile(path.join(process.cwd(), "assets", "fonts", "young-serif-400.woff")),
]);

async function png(element: React.ReactElement, width: number, height: number, fonts = true): Promise<Uint8Array> {
  const [, serif] = await assets;
  const response = new ImageResponse(element, {
    width, height,
    ...(fonts ? { fonts: [{ name: "Young Serif", data: serif, weight: 400 as const, style: "normal" as const }] } : {}),
  });
  return new Uint8Array(await response.arrayBuffer());
}

/** icon, logo and strip at @1x/@2x/@3x as Wallet expects. */
export async function passImages(style: Record<string, unknown>, photo: Buffer | null): Promise<Record<string, Uint8Array>> {
  const [icon] = await assets;
  const iconSrc = `data:image/png;base64,${icon.toString("base64")}`;
  const look = webStyle(style, !!photo);
  const photoSrc = photo ? `data:image/jpeg;base64,${photo.toString("base64")}` : null;

  const iconImage = (size: number) =>
    // eslint-disable-next-line @next/next/no-img-element
    png(<img src={iconSrc} width={size} height={size} style={{ borderRadius: size * 0.22 }} />, size, size, false);

  const logo = (scale: number) =>
    png(
      <div style={{ display: "flex", alignItems: "center", width: 160 * scale, height: 50 * scale, gap: 8 * scale }}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={iconSrc} width={30 * scale} height={30 * scale} style={{ borderRadius: 7 * scale }} />
      </div>,
      160 * scale, 50 * scale,
    );

  // Event tickets with a square barcode get a 375 × 98 pt strip.
  const strip = (scale: number) =>
    png(
      <div style={{ display: "flex", width: 375 * scale, height: 98 * scale, position: "relative", background: look.background }}>
        {look.useImage && photoSrc ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={photoSrc} width={375 * scale} height={98 * scale} style={{ position: "absolute", inset: 0, objectFit: "cover" }} />
        ) : null}
        <div style={{ position: "absolute", inset: 0, display: "flex",
          background: "linear-gradient(180deg, rgba(20,6,10,0.15) 0%, rgba(20,6,10,0.55) 100%)" }} />
      </div>,
      375 * scale, 98 * scale, false,
    );

  const [i1, i2, i3, l1, l2, l3, s1, s2, s3] = await Promise.all([
    iconImage(29), iconImage(58), iconImage(87), logo(1), logo(2), logo(3), strip(1), strip(2), strip(3),
  ]);
  return {
    "icon.png": i1, "icon@2x.png": i2, "icon@3x.png": i3,
    "logo.png": l1, "logo@2x.png": l2, "logo@3x.png": l3,
    "strip.png": s1, "strip@2x.png": s2, "strip@3x.png": s3,
  };
}
