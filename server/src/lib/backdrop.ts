// Server-drawn images (link previews, Wallet strips) can't fetch /scenes/... the way a browser does,
// so they get the backdrop inlined: the uploaded photo, or the built-in scene's pre-rendered JPEG.
import { readFile } from "node:fs/promises";
import path from "node:path";
import type { WebStyle } from "./style.ts";

const scenes = new Map<string, Promise<string | null>>();

function sceneDataURL(scene: string): Promise<string | null> {
  if (!scenes.has(scene)) {
    scenes.set(
      scene,
      readFile(path.join(process.cwd(), "public", "scenes", `${scene}.jpg`))
        .then((jpeg) => `data:image/jpeg;base64,${jpeg.toString("base64")}`)
        .catch(() => null),
    );
  }
  return scenes.get(scene)!;
}

/** A data URL for the image behind the countdown, or null to draw `baseBackground` alone. */
export async function backdropSrc(look: WebStyle, photo: Buffer | null): Promise<string | null> {
  if (look.useImage && photo) return `data:image/jpeg;base64,${photo.toString("base64")}`;
  return look.scene ? sceneDataURL(look.scene) : null;
}
