// The words of a recap, shared by the server and the live page's client code. No database here, so
// the browser can import it.
import type { CountdownDoc } from "./countdowns.ts";

export interface Recap {
  /** How long it was counted, from when it was made to zero. Left out for public crypt entries. */
  counted?: { days: number; hours: number };
  /** Everyone who counted down: the owner plus members, or subscribers for a public entry. */
  people: number;
  /** Notes and photos in the coffin, opened at zero. */
  notes: number;
  /** The closest guess or guesses, once a pool is settled. */
  closest: string[];
}

/** Zero has passed. A countdown kept counting up after zero still has its recap. */
export function isFinished(doc: Pick<CountdownDoc, "kind" | "targetDate" | "keptCounting">, now = new Date()): boolean {
  if (doc.keptCounting) return true;
  return doc.kind !== "countUp" && doc.targetDate.getTime() <= now.getTime();
}

export function countedSpan(created: Date, target: Date): { days: number; hours: number } {
  const seconds = Math.max(0, Math.floor((target.getTime() - created.getTime()) / 1000));
  return { days: Math.floor(seconds / 86_400), hours: Math.floor(seconds / 3_600) };
}

const plural = (n: number, one: string, many = `${one}s`) => `${n.toLocaleString("en-US")} ${n === 1 ? one : many}`;

function names(list: string[]): string {
  if (list.length <= 2) return list.join(" and ");
  return `${list.slice(0, -1).join(", ")} and ${list[list.length - 1]}`;
}

/**
 * The words: "142 days counted", and "23 of us · 41 notes in the coffin · Dana guessed closest".
 * Pure, for tests. `isPublic` speaks of everyone counting rather than "us".
 */
export function recapText(recap: Recap, isPublic = false): { counted: string | null; people: string | null; together: string | null } {
  const counted = recap.counted
    ? recap.counted.days >= 1
      ? `${plural(recap.counted.days, "day")} counted`
      : recap.counted.hours >= 1
        ? `${plural(recap.counted.hours, "hour")} counted`
        : null
    : null;
  const parts: string[] = [];
  if (recap.people > 1) parts.push(isPublic ? `${recap.people.toLocaleString("en-US")} counted down` : `${recap.people.toLocaleString("en-US")} of us`);
  if (recap.notes > 0) parts.push(`${plural(recap.notes, "note")} in the coffin`);
  if (recap.closest.length) parts.push(`${names(recap.closest.slice(0, 3))} guessed closest`);
  const together = recap.people > 1 ? `${recap.people.toLocaleString("en-US")} counted down together` : null;
  return { counted, people: parts.length ? parts.join(" · ") : null, together };
}
