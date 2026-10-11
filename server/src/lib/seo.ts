// What search engines and AI answers read on a public countdown: the day it happens written out in
// the HTML (the live date line waits for the viewer's clock), and a schema.org description.
// Pure and browser-safe: the live page imports it too.
import type { PublicCountdown } from "./countdowns.ts";

type Dated = Pick<PublicCountdown, "targetDate" | "floating">;

/** "Halloween 2026", unless the title already names a year. */
export function titleWithYear(title: string, c: Dated): string {
  return /\b\d{4}\b/.test(title) ? title : `${title} ${new Date(c.targetDate).getUTCFullYear()}`;
}

/**
 * The day it happens, the same on the server and on the first browser render. Floating times are
 * wall-clock times stored as UTC, so the date alone is right everywhere; exact moments say "UTC".
 */
export function eventDateText(c: Dated, locale: string): string {
  const date = new Date(c.targetDate);
  return c.floating
    ? date.toLocaleDateString(locale, { weekday: "long", month: "long", day: "numeric", year: "numeric", timeZone: "UTC" })
    : date.toLocaleString(locale, {
        weekday: "long", month: "long", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit",
        timeZone: "UTC", timeZoneName: "short",
      });
}

/**
 * A WebPage about the event. Not a bare Event: Google's event results want a venue, and a holiday
 * has none, so the Event rides along as what the page is about.
 */
export function countdownJsonLd(c: PublicCountdown, url: string, image: string) {
  const name = titleWithYear(c.title, c);
  return {
    "@context": "https://schema.org",
    "@type": "WebPage",
    name: `${name} countdown`,
    url,
    image,
    isPartOf: { "@type": "WebSite", name: "Count Downcula", url: "https://www.countdowncula.com/" },
    about: {
      "@type": "Event",
      name,
      // Floating times happen at each place's own midnight: a date, not a moment.
      startDate: c.floating ? c.floating.slice(0, 10) : c.targetDate,
      ...(c.details ? { description: c.details } : {}),
    },
  };
}

/** JSON for a `<script type="application/ld+json">`, safe against a title that says `</script>`. */
export const jsonLdHTML = (data: unknown) => JSON.stringify(data).replace(/</g, "\\u003c");
