// Present mode (5.9): a countdown full screen on a TV, a projector or a laptop, with a QR code in
// the corner so people in the room can join from their phones. Pure helpers, for tests.
import qrcode from "qrcode-generator";

/** A QR code as one SVG path on a `size` × `size` grid of modules, quiet zone included. */
export function qrPath(text: string, margin = 2): { size: number; path: string } {
  const qr = qrcode(0, "M");
  qr.addData(text);
  qr.make();
  const n = qr.getModuleCount();
  const parts: string[] = [];
  for (let row = 0; row < n; row++) {
    // Runs of dark modules on a row become one rectangle each, which keeps the path short.
    let col = 0;
    while (col < n) {
      if (!qr.isDark(row, col)) { col++; continue; }
      const start = col;
      while (col < n && qr.isDark(row, col)) col++;
      parts.push(`M${start + margin} ${row + margin}h${col - start}v1h-${col - start}z`);
    }
  }
  return { size: n + margin * 2, path: parts.join("") };
}

/** The live page link the room's QR code opens, tagged so joins from the room can be counted. */
export function roomLink(liveURL: string): string {
  const url = new URL(liveURL);
  url.searchParams.set("src", "present");
  return url.toString();
}

/**
 * What the big screen shows at a moment: the usual readout, the final ten seconds as one huge
 * number, or zero. `finalSecond` is 10...1 in the last ten seconds, else null.
 */
export function presentPhase(now: Date, target: Date, countsUp: boolean): { phase: "counting" | "final" | "zero"; finalSecond: number | null } {
  if (countsUp) return { phase: "counting", finalSecond: null };
  const left = (target.getTime() - now.getTime()) / 1000;
  if (left <= 0) return { phase: "zero", finalSecond: null };
  if (left <= 10) return { phase: "final", finalSecond: Math.ceil(left) };
  return { phase: "counting", finalSecond: null };
}
