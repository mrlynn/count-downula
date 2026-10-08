// Date pools: friends guess when something will happen (the baby, the ship date, the first snow).
// The owner sets the real date when it's known and the closest guess wins. Bragging rights only:
// no money, entry fees or prizes.
//
// Anyone with the link can guess, from the app or the web. A guesser is whoever holds a token: the
// owner's or a member's key in the app, or one this server hands a browser on its first guess.
import { randomBytes } from "node:crypto";
import { ObjectId, type Collection } from "mongodb";
import { hashToken, type CountdownDoc } from "./countdowns.ts";
export type { PoolState } from "./countdowns.ts";
import { db } from "./mongo.ts";

export const POOL_LIMITS = {
  name: 40,
  /** Guesses per pool, so one link can't fill the store. */
  perPool: 300,
  /** How far ahead a guess may go. */
  maxYearsAhead: 10,
};

export interface GuessDoc {
  _id: ObjectId;
  slug: string;
  tokenHash: string;
  name: string;
  guess: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface PublicGuess {
  id: string;
  name: string;
  guess: string;
  mine: boolean;
  /** Once settled: how far off, and the place (1 is the winner; ties share a place). */
  offBySeconds?: number;
  place?: number;
}

let indexesReady: Promise<unknown> | undefined;

export async function guesses(): Promise<Collection<GuessDoc>> {
  const collection = (await db()).collection<GuessDoc>("guesses");
  indexesReady ??= collection.createIndex({ slug: 1, tokenHash: 1 }, { unique: true });
  await indexesReady;
  return collection;
}

export function newGuesserToken(): string {
  return randomBytes(32).toString("base64url");
}

/** Checks a guess. Pure, for tests. */
export function validateGuess(body: unknown, now = new Date()): { ok: true; value: { name: string; guess: Date } } | { ok: false; error: string } {
  if (!body || typeof body !== "object") return { ok: false, error: "Send a JSON body." };
  const b = body as Record<string, unknown>;
  const name = typeof b.name === "string" ? b.name.trim() : "";
  if (!name) return { ok: false, error: "Add your name so people know whose guess it is." };
  if (name.length > POOL_LIMITS.name) return { ok: false, error: `Names are limited to ${POOL_LIMITS.name} characters.` };
  const guess = typeof b.guess === "string" ? new Date(b.guess) : null;
  if (!guess || Number.isNaN(guess.getTime())) return { ok: false, error: "guess must be an ISO 8601 date." };
  const latest = new Date(now);
  latest.setUTCFullYear(latest.getUTCFullYear() + POOL_LIMITS.maxYearsAhead);
  if (guess > latest) return { ok: false, error: "That guess is too far away." };
  if (guess.getTime() < now.getTime() - 86_400_000) return { ok: false, error: "Guess a date that hasn't passed." };
  return { ok: true, value: { name, guess } };
}

export type PoolAction = { action: "close" } | { action: "reopen" } | { action: "settle"; answer: Date };

/** Checks an owner's pool action. Pure, for tests. */
export function validatePoolAction(body: unknown): { ok: true; value: PoolAction } | { ok: false; error: string } {
  if (!body || typeof body !== "object") return { ok: false, error: "Send a JSON body." };
  const b = body as Record<string, unknown>;
  if (b.action === "close" || b.action === "reopen") return { ok: true, value: { action: b.action } };
  if (b.action === "settle") {
    const answer = typeof b.answer === "string" ? new Date(b.answer) : null;
    if (!answer || Number.isNaN(answer.getTime())) return { ok: false, error: "answer must be an ISO 8601 date." };
    return { ok: true, value: { action: "settle", answer } };
  }
  return { ok: false, error: "action must be close, reopen or settle." };
}

/**
 * The guesses as anyone sees them: by guessed date while the pool runs, and by how close they came
 * once it's settled. Ties share a place, so two people can both win.
 */
export function rankGuesses(docs: GuessDoc[], answer: Date | undefined, viewerHash: string | null): PublicGuess[] {
  const base = (g: GuessDoc): PublicGuess => ({
    id: g._id.toHexString(),
    name: g.name,
    guess: g.guess.toISOString(),
    mine: viewerHash === g.tokenHash,
  });
  if (!answer) return [...docs].sort((a, b) => a.guess.getTime() - b.guess.getTime()).map(base);
  const off = (g: GuessDoc) => Math.round(Math.abs(g.guess.getTime() - answer.getTime()) / 1000);
  const sorted = [...docs].sort((a, b) => off(a) - off(b) || a.createdAt.getTime() - b.createdAt.getTime());
  let place = 0;
  let last = -1;
  return sorted.map((g, i) => {
    if (off(g) !== last) {
      place = i + 1;
      last = off(g);
    }
    return { ...base(g), offBySeconds: off(g), place };
  });
}

/** The guess list and the asker's own token hash, for GET. */
export async function poolGuesses(doc: CountdownDoc, token: string | null) {
  const viewer = token ? hashToken(token) : null;
  const all = await (await guesses()).find({ slug: doc.slug }).toArray();
  return rankGuesses(all, doc.pool?.answer, viewer);
}

export async function purgePool(slug: string) {
  await (await guesses()).deleteMany({ slug });
}
