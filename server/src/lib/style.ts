// Turns the app's CountdownStyle JSON (Swift Codable) into CSS values.
// Swift encodes enums with associated values as {"case":{"_0":value}}.

export interface RGBA {
  red: number;
  green: number;
  blue: number;
  opacity?: number;
}

export interface WebStyle {
  /** CSS background when there is no image to show. */
  background: string;
  /** Whether the uploaded backdrop image (photo or rendered scene) should be drawn. */
  useImage: boolean;
  text: string;
  accent: string;
  fontFamily: string;
  fontWeight: number;
  lightText: boolean;
}

export const BLOOD: RGBA = { red: 0.85, green: 0.09, blue: 0.2 };
const NIGHT = { stops: [{ red: 0.3, green: 0.04, blue: 0.12 }, { red: 0.06, green: 0.02, blue: 0.05 }], angle: 45 };

const clamp = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.min(Math.max(v, 0), 1) : 0);

export function rgba(c: RGBA): string {
  const ch = (v: number) => Math.round(clamp(v) * 255);
  const a = c.opacity === undefined ? 1 : clamp(c.opacity);
  return `rgba(${ch(c.red)}, ${ch(c.green)}, ${ch(c.blue)}, ${a})`;
}

function isColor(v: unknown): v is RGBA {
  return !!v && typeof v === "object" && "red" in v && "green" in v && "blue" in v;
}

/** Swift's angle: 0 runs left to right, 90 top to bottom. CSS: 90deg is to the right, 180deg down. */
export function gradientCss(spec: { stops: RGBA[]; angle?: number }): string {
  const stops = spec.stops.filter(isColor).map(rgba);
  if (stops.length === 0) return gradientCss(NIGHT);
  if (stops.length === 1) stops.push(stops[0]);
  const angle = ((spec.angle ?? 135) + 90) % 360;
  return `linear-gradient(${angle}deg, ${stops.join(", ")})`;
}

const FONTS: Record<string, string> = {
  rounded: `ui-rounded, "SF Pro Rounded", "Instrument Sans", system-ui, sans-serif`,
  serif: `"Young Serif", Georgia, serif`,
  mono: `ui-monospace, "SF Mono", Menlo, monospace`,
  classic: `"Instrument Sans", system-ui, sans-serif`,
  condensed: `"Instrument Sans", system-ui, sans-serif`,
  expanded: `"Instrument Sans", system-ui, sans-serif`,
};

/** Scenes with a pre-rendered image in public/scenes (scripts/render-scenes.swift). */
const SCENES = new Set(["midnight", "starfield", "aurora", "sunset", "mountains", "ocean", "snowfall", "blossoms",
  "city", "confetti", "balloons", "harvestMoon"]);

const WEIGHTS: Record<string, number> = { regular: 400, medium: 500, semibold: 600, bold: 700, heavy: 800, black: 900 };

export function webStyle(style: unknown, hasImage: boolean): WebStyle {
  const s = (style && typeof style === "object" ? style : {}) as Record<string, unknown>;
  const bg = (s.background && typeof s.background === "object" ? s.background : { automatic: {} }) as Record<
    string,
    { _0?: unknown }
  >;
  const kind = Object.keys(bg)[0] ?? "automatic";
  const payload = bg[kind]?._0;

  let background = gradientCss(NIGHT);
  let useImage = false;
  switch (kind) {
    case "automatic":
    case "photo":
    case "scene":
      // The app uploads its rendered scene as the backdrop image, so scenes look the same on the web.
      // Without one (crypt entries, older links), use the same scene rendered once from the app's code.
      useImage = hasImage;
      if (!hasImage && typeof payload === "string" && SCENES.has(payload)) {
        background = `center / cover no-repeat url(/scenes/${payload}.jpg), ${background}`;
      }
      break;
    case "gradient":
      if (payload && typeof payload === "object" && Array.isArray((payload as { stops?: unknown }).stops)) {
        background = gradientCss(payload as { stops: RGBA[]; angle?: number });
      }
      break;
    case "solid":
      if (isColor(payload)) background = rgba(payload);
      break;
  }

  const textColor = isColor(s.textColor) ? s.textColor : { red: 1, green: 1, blue: 1 };
  const luminance = 0.2126 * clamp(textColor.red) + 0.7152 * clamp(textColor.green) + 0.0722 * clamp(textColor.blue);
  return {
    background,
    useImage,
    text: rgba(textColor),
    accent: rgba(isColor(s.accent) ? s.accent : BLOOD),
    fontFamily: FONTS[String(s.font)] ?? FONTS.rounded,
    fontWeight: WEIGHTS[String(s.weight)] ?? 700,
    lightText: luminance > 0.5,
  };
}
