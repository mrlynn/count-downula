import { events, type EventName } from "./events.ts";

/** The aggregations behind /admin/metrics. Each one reads the `events` collection only. */

const DAY = 86_400_000;
const daysAgo = (days: number, now: Date) => new Date(now.getTime() - days * DAY);

export interface MonthRow {
  month: string;
  activeInstalls: number;
  publishes: number;
  joins: number;
  /** The north star: countdowns shared per active install that month. */
  sharedPerActive: number | null;
}

/** "2026-10" for the month a date falls in, in UTC. */
export const monthKey = (d: Date) => d.toISOString().slice(0, 7);

export async function monthly(months = 6, now = new Date()): Promise<MonthRow[]> {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - (months - 1), 1));
  const collection = await events();
  const [active, counts] = await Promise.all([
    collection.aggregate<{ _id: Date; installs: number }>([
      { $match: { name: "active", at: { $gte: start } } },
      { $group: { _id: { month: { $dateTrunc: { date: "$at", unit: "month" } }, installId: "$installId" } } },
      { $group: { _id: "$_id.month", installs: { $sum: 1 } } },
    ]).toArray(),
    collection.aggregate<{ _id: { month: Date; name: EventName }; n: number }>([
      { $match: { name: { $in: ["publish", "join"] }, at: { $gte: start } } },
      { $group: { _id: { month: { $dateTrunc: { date: "$at", unit: "month" } }, name: "$name" }, n: { $sum: 1 } } },
    ]).toArray(),
  ]);
  const rows: MonthRow[] = [];
  for (let i = 0; i < months; i++) {
    const month = monthKey(new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth() + i, 1)));
    const activeInstalls = active.find((a) => monthKey(a._id) === month)?.installs ?? 0;
    const count = (name: EventName) => counts.find((c) => monthKey(c._id.month) === month && c._id.name === name)?.n ?? 0;
    const publishes = count("publish");
    rows.push({ month, activeInstalls, publishes, joins: count("join"), sharedPerActive: activeInstalls ? publishes / activeInstalls : null });
  }
  return rows.reverse();
}

/** How many times each event happened in the last `days`, split by platform. */
export async function totals(days = 30, now = new Date()): Promise<Map<EventName, Map<string, number>>> {
  const rows = await (await events()).aggregate<{ _id: { name: EventName; platform: string }; n: number }>([
    { $match: { at: { $gte: daysAgo(days, now) } } },
    { $group: { _id: { name: "$name", platform: "$platform" }, n: { $sum: 1 } } },
  ]).toArray();
  const out = new Map<EventName, Map<string, number>>();
  for (const r of rows) {
    const byPlatform = out.get(r._id.name) ?? new Map<string, number>();
    byPlatform.set(r._id.platform, r.n);
    out.set(r._id.name, byPlatform);
  }
  return out;
}

export const sum = (m: Map<string, number> | undefined) => [...(m?.values() ?? [])].reduce((a, b) => a + b, 0);

/** The top values of `source` for one event: where page views came from, how countdowns get made. */
export async function sources(name: EventName, days = 30, now = new Date(), limit = 10) {
  return (await events()).aggregate<{ _id: string | null; n: number }>([
    { $match: { name, at: { $gte: daysAgo(days, now) } } },
    { $group: { _id: "$source", n: { $sum: 1 } } },
    { $sort: { n: -1 } },
    { $limit: limit },
  ]).toArray();
}

/** How many of each event carried each unit in the last `days`: countdowns made, switched and shared by unit (5.8). */
export async function unitCounts(names: EventName[], days = 30, now = new Date()) {
  const rows = await (await events()).aggregate<{ _id: { name: EventName; unit: string }; n: number }>([
    { $match: { name: { $in: names }, unit: { $exists: true }, at: { $gte: daysAgo(days, now) } } },
    { $group: { _id: { name: "$name", unit: "$unit" }, n: { $sum: 1 } } },
  ]).toArray();
  const out = new Map(rows.map((r) => [`${r._id.name}:${r._id.unit}`, r.n]));
  return (name: EventName, unit: string) => out.get(`${name}:${unit}`) ?? 0;
}

/** How many of each event had each source in the last `days`: `{ countdown_deleted: { after_zero_30d: 4 } }`. */
export async function sourceCounts(names: EventName[], days = 30, now = new Date()) {
  const rows = await (await events()).aggregate<{ _id: { name: EventName; source: string | null }; n: number }>([
    { $match: { name: { $in: names }, at: { $gte: daysAgo(days, now) } } },
    { $group: { _id: { name: "$name", source: "$source" }, n: { $sum: 1 } } },
  ]).toArray();
  const out = new Map<string, number>();
  for (const r of rows) out.set(`${r._id.name}:${r._id.source ?? ""}`, r.n);
  return (name: EventName, source?: string) =>
    source === undefined
      ? [...out.entries()].filter(([k]) => k.startsWith(`${name}:`)).reduce((a, [, n]) => a + n, 0)
      : out.get(`${name}:${source}`) ?? 0;
}

export interface NewInstalls {
  total: number;
  fromLink: number;
}

/** Installs first seen in the last `days`, and how many of them opened with a link waiting. */
export async function newInstalls(days = 30, now = new Date()): Promise<NewInstalls> {
  const [row] = await (await events()).aggregate<NewInstalls>([
    { $match: { installId: { $exists: true } } },
    {
      $group: {
        _id: "$installId",
        first: { $min: "$at" },
        fromLink: { $max: { $cond: [{ $eq: ["$name", "install_from_link"] }, 1, 0] } },
      },
    },
    { $match: { first: { $gte: daysAgo(days, now) } } },
    { $group: { _id: null, total: { $sum: 1 }, fromLink: { $sum: "$fromLink" } } },
  ]).toArray();
  return row ?? { total: 0, fromLink: 0 };
}

export interface Cohort {
  /** Monday of the week the install was first seen, "2026-10-05". */
  week: string;
  size: number;
  /** Share of the cohort active in week 0, 1, 2… after it started. Null for weeks still to come. */
  retained: (number | null)[];
}

/** Weekly cohorts by first event, with retention from the daily `active` ping. */
export async function cohorts(weeks = 8, now = new Date()): Promise<Cohort[]> {
  const rows = await (await events()).aggregate<{ first: Date; activeWeeks: Date[] }>([
    { $match: { installId: { $exists: true } } },
    {
      $group: {
        _id: "$installId",
        first: { $min: "$at" },
        activeWeeks: {
          $addToSet: { $cond: [{ $eq: ["$name", "active"] }, { $dateTrunc: { date: "$at", unit: "week", startOfWeek: "monday" } }, "$$REMOVE"] },
        },
      },
    },
    { $project: { _id: 0, first: { $dateTrunc: { date: "$first", unit: "week", startOfWeek: "monday" } }, activeWeeks: 1 } },
  ]).toArray();
  return buildCohorts(rows, weeks, now);
}

/** Separate from the query so it can be tested without a database. */
export function buildCohorts(rows: { first: Date; activeWeeks: Date[] }[], weeks: number, now: Date): Cohort[] {
  const WEEK = 7 * DAY;
  const thisWeek = startOfWeek(now);
  const out: Cohort[] = [];
  for (let i = weeks - 1; i >= 0; i--) {
    const start = thisWeek.getTime() - i * WEEK;
    const members = rows.filter((r) => r.first.getTime() === start);
    const retained = Array.from({ length: weeks }, (_, offset) => {
      const week = start + offset * WEEK;
      if (week > thisWeek.getTime()) return null;
      if (!members.length) return 0;
      return members.filter((m) => m.activeWeeks.some((w) => w.getTime() === week)).length / members.length;
    });
    out.push({ week: new Date(start).toISOString().slice(0, 10), size: members.length, retained });
  }
  return out.reverse();
}

/** Monday 00:00 UTC of the week `d` falls in, the same week $dateTrunc uses. */
export function startOfWeek(d: Date): Date {
  const day = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  const weekday = (new Date(day).getUTCDay() + 6) % 7;
  return new Date(day - weekday * DAY);
}
