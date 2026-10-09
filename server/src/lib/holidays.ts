// The Crypt's yearly holidays and fun days, as rules instead of dates, so they come back every year
// without anyone reseeding them. A daily cron (GET /api/cron/crypt) keeps the next occurrence of
// each one in the Crypt: the day after Halloween 2026 drops off, Halloween 2027 is there. Sky
// events and sports don't follow rules and stay hand-curated in crypt/launch.json. Pure, for tests.
import { isCurrent, type CategorySlug, type CryptInput } from "./crypt.ts";

interface HolidayRule {
  /** The slug before the year: "halloween" → "halloween-2027". */
  id: string;
  title: (year: number) => string;
  details: (year: number) => string;
  category: CategorySlug;
  scene: string;
  /** The floating local time it happens in a year, "YYYY-MM-DDTHH:mm:ss", or null if unknown. */
  local: (year: number) => string | null;
}

const pad = (n: number) => String(n).padStart(2, "0");
const at = (year: number, month: number, day: number, time = "00:00:00") => `${year}-${pad(month)}-${pad(day)}T${time}`;
const fixed = (month: number, day: number, time?: string) => (year: number) => at(year, month, day, time);

/** The nth weekday (0 Sunday … 6 Saturday) of a month: Thanksgiving is the 4th Thursday of November. */
export function nthWeekday(year: number, month: number, weekday: number, n: number): number {
  const first = new Date(Date.UTC(year, month - 1, 1)).getUTCDay();
  return 1 + ((weekday - first + 7) % 7) + (n - 1) * 7;
}

/** Lunar New Year follows the lunisolar calendar, so its dates are looked up, not worked out. */
export const LUNAR_NEW_YEAR: Record<number, string> = {
  2027: "02-06", 2028: "01-26", 2029: "02-13", 2030: "02-03", 2031: "01-23",
  2032: "02-11", 2033: "01-31", 2034: "02-19", 2035: "02-08",
};
const ZODIAC = ["Rat", "Ox", "Tiger", "Rabbit", "Dragon", "Snake", "Horse", "Goat", "Monkey", "Rooster", "Dog", "Pig"];
export const zodiac = (year: number) => ZODIAC[(((year - 4) % 12) + 12) % 12];

const none = () => "";

export const HOLIDAY_RULES: HolidayRule[] = [
  { id: "halloween", title: () => "Halloween", details: () => "The Count's favorite night of the year.",
    category: "holidays", scene: "harvestMoon", local: fixed(10, 31) },
  { id: "dst-ends", title: () => "Daylight Saving Time Ends (US)",
    details: () => "Clocks fall back an hour. One more hour of darkness, you're welcome.",
    category: "holidays", scene: "midnight", local: (y) => at(y, 11, nthWeekday(y, 11, 0, 1), "02:00:00") },
  { id: "dia-de-muertos", title: () => "Día de los Muertos", details: () => "Remembering the ones we love, November 1 and 2.",
    category: "holidays", scene: "harvestMoon", local: fixed(11, 2) },
  { id: "thanksgiving", title: () => "Thanksgiving (US)", details: () => "The fourth Thursday of November.",
    category: "holidays", scene: "mountains", local: (y) => at(y, 11, nthWeekday(y, 11, 4, 4)) },
  { id: "christmas", title: () => "Christmas", details: none, category: "holidays", scene: "snowfall", local: fixed(12, 25) },
  { id: "new-year", title: (y) => `New Year ${y}`, details: () => "Midnight, wherever you are.",
    category: "holidays", scene: "confetti", local: fixed(1, 1) },
  { id: "lunar-new-year", title: () => "Lunar New Year", details: (y) => `Welcome the Year of the ${zodiac(y)}.`,
    category: "holidays", scene: "confetti", local: (y) => (LUNAR_NEW_YEAR[y] ? `${y}-${LUNAR_NEW_YEAR[y]}T00:00:00` : null) },
  { id: "valentines", title: () => "Valentine's Day", details: none, category: "holidays", scene: "blossoms", local: fixed(2, 14) },
  { id: "pi-day", title: () => "Pi Day", details: () => "3.14, at 1:59.", category: "fun", scene: "starfield",
    local: fixed(3, 14, "13:59:00") },
  { id: "st-patricks", title: () => "St. Patrick's Day", details: none, category: "holidays", scene: "mountains", local: fixed(3, 17) },
  { id: "april-fools", title: () => "April Fools' Day", details: () => "Trust no countdown.", category: "fun", scene: "balloons",
    local: fixed(4, 1) },
  { id: "star-wars-day", title: () => "Star Wars Day", details: () => "May the Fourth be with you.", category: "fun",
    scene: "starfield", local: fixed(5, 4) },
];

/**
 * The occurrence of each holiday the Crypt should show now: this year's while it's still current
 * (not past, or past within a day), otherwise next year's. A holiday with no known date (Lunar New
 * Year past the table) is left out.
 */
export function upcomingHolidays(now = new Date()): CryptInput[] {
  const year = now.getUTCFullYear();
  const out: CryptInput[] = [];
  for (const rule of HOLIDAY_RULES) {
    for (const y of [year - 1, year, year + 1]) {
      const local = rule.local(y);
      if (!local) continue;
      if (!isCurrent({ targetDate: new Date(`${local}Z`), floating: local }, now)) continue;
      out.push({ slug: `${rule.id}-${y}`, title: rule.title(y), details: rule.details(y), category: rule.category, scene: rule.scene, local });
      break;
    }
  }
  return out;
}
