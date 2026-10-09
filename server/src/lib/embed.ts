// Embeds: a small live countdown for other people's websites, at /embed/<slug>. Options come in
// the query string, so the one-line script and a hand-written iframe work the same way.

export type EmbedTheme = "style" | "dark" | "light";
/**
 * What the embed shows at zero: a message, the recap, a count up from zero, or nothing. "redirect"
 * (hosted countdowns, script embeds only) asks the page it's on to go to its `data-redirect` URL,
 * and shows the message until it does.
 */
export type EmbedEnd = "message" | "recap" | "countup" | "hide" | "redirect";

export interface EmbedOptions {
  theme: EmbedTheme;
  end: EmbedEnd;
  /** The message at zero, when `end` is "message". */
  message: string;
}

export const EMBED_MESSAGE_LIMIT = 80;

/** Reads the query string, falling back to defaults for anything missing or unknown. Pure, for tests. */
export function embedOptions(query: Record<string, string | string[] | undefined>): EmbedOptions {
  const one = (key: string) => (typeof query[key] === "string" ? (query[key] as string) : undefined);
  const theme = one("theme");
  const end = one("end");
  const message = (one("message") ?? "").replace(/[\u0000-\u001f]/g, " ").trim().slice(0, EMBED_MESSAGE_LIMIT);
  return {
    theme: theme === "dark" || theme === "light" ? theme : "style",
    end: end === "recap" || end === "countup" || end === "hide" || end === "redirect" ? end : "message",
    message: message || "It's here!",
  };
}

/**
 * Plain count-ups (sober, smoke-free) aren't embeddable: they're often private milestones. A
 * countdown kept counting up after its zero is fine.
 */
export function embeddable(doc: { kind: string; keptCounting?: boolean }): boolean {
  return doc.kind !== "countUp" || doc.keptCounting === true;
}

/** The snippet people paste: a script tag that drops in the iframe. */
export function embedSnippet(origin: string, slug: string): string {
  return `<script async src="${origin}/embed.js" data-countdown="${slug}"></script>`;
}
