"use client";

import { Alert, Box, Button, Stack, TextField, Typography } from "@mui/material";
import { useCallback, useEffect, useState } from "react";

interface Guess {
  id: string;
  name: string;
  guess: string;
  mine: boolean;
  offBySeconds?: number;
  place?: number;
}

interface Pool {
  closed: boolean;
  answer: string | null;
  guesses: Guess[];
}

// The key the server hands this browser with its first guess, so it can change that guess later.
const tokenKey = (slug: string) => `pool-token:${slug}`;
const nameKey = "pool-name";

function storage(): Storage | null {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

/** "2026-11-30T16:00" in the viewer's own time, for a datetime-local input. */
function localInputValue(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function offBy(seconds: number): string {
  if (seconds < 60) return "spot on";
  const days = Math.floor(seconds / 86_400);
  const hours = Math.floor((seconds % 86_400) / 3_600);
  const minutes = Math.floor((seconds % 3_600) / 60);
  if (days > 0) return `off by ${days}d ${hours}h`;
  if (hours > 0) return `off by ${hours}h ${minutes}m`;
  return `off by ${minutes}m`;
}

const when = (iso: string) =>
  new Date(iso).toLocaleString(undefined, { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });

/** Guess when it happens. Anyone with the link can; the closest guess wins once the owner sets the date. */
export default function PoolPanel({ slug, estimate }: { slug: string; estimate: string }) {
  const [pool, setPool] = useState<Pool | null>(null);
  const [name, setName] = useState("");
  const [guess, setGuess] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    const token = storage()?.getItem(tokenKey(slug));
    const res = await fetch(`/api/countdowns/${slug}/pool`, { headers: token ? { Authorization: `Bearer ${token}` } : {} });
    if (res.ok) setPool(await res.json());
  }, [slug]);

  useEffect(() => {
    setName(storage()?.getItem(nameKey) ?? "");
    setGuess(localInputValue(new Date(estimate)));
    load();
  }, [estimate, load]);

  const mine = pool?.guesses.find((g) => g.mine);
  useEffect(() => {
    if (mine) setGuess(localInputValue(new Date(mine.guess)));
  }, [mine?.guess]); // eslint-disable-line react-hooks/exhaustive-deps

  async function submit(e: { preventDefault(): void }) {
    e.preventDefault();
    setError(null);
    setSaving(true);
    try {
      const token = storage()?.getItem(tokenKey(slug));
      const res = await fetch(`/api/countdowns/${slug}/pool/guesses`, {
        method: "POST",
        headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify({ name: name.trim(), guess: new Date(guess).toISOString() }),
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) {
        setError(body.error ?? "Couldn't save your guess.");
        return;
      }
      if (body.token) storage()?.setItem(tokenKey(slug), body.token);
      storage()?.setItem(nameKey, name.trim());
      await load();
    } finally {
      setSaving(false);
    }
  }

  if (!pool) return null;
  const settled = Boolean(pool.answer);
  const winners = pool.guesses.filter((g) => g.place === 1);

  return (
    <Box sx={{ bgcolor: "background.paper", px: { xs: 2, sm: 4 }, py: { xs: 4, sm: 5 } }}>
      <Box sx={{ maxWidth: 960, mx: "auto" }}>
        <Typography variant="h2" sx={{ fontFamily: `"Young Serif", Georgia, serif`, fontSize: { xs: 26, sm: 32 }, mb: 1 }}>
          {settled ? "The results are in" : "Guess the date"}
        </Typography>
        <Typography sx={{ opacity: 0.75, mb: 3 }}>
          {settled
            ? winners.length > 0
              ? `${winners.map((w) => w.name).join(" and ")} called it closest. It happened ${when(pool.answer!)}.`
              : `It happened ${when(pool.answer!)}.`
            : pool.closed
              ? "Guessing is closed. The closest guess wins once the real date is in."
              : "When do you think it'll happen? The closest guess wins bragging rights."}
        </Typography>

        {!pool.closed ? (
          <Stack component="form" onSubmit={submit} direction={{ xs: "column", sm: "row" }} spacing={1.5} sx={{ mb: 3 }}>
            <TextField
              label="Your name"
              value={name}
              onChange={(e) => setName(e.target.value.slice(0, 40))}
              required
              size="small"
            />
            <TextField
              label="Your guess"
              type="datetime-local"
              value={guess}
              onChange={(e) => setGuess(e.target.value)}
              required
              size="small"
              slotProps={{ inputLabel: { shrink: true } }}
            />
            <Button type="submit" variant="contained" disabled={saving || !name.trim() || !guess}>
              {mine ? "Change my guess" : "Lock it in"}
            </Button>
          </Stack>
        ) : null}
        {error ? <Alert severity="error" sx={{ mb: 2 }}>{error}</Alert> : null}

        {pool.guesses.length === 0 ? (
          <Typography sx={{ opacity: 0.6 }}>No guesses yet. Be the first.</Typography>
        ) : (
          <Stack spacing={1}>
            {pool.guesses.map((g) => (
              <Stack
                key={g.id}
                direction="row"
                spacing={2}
                sx={{
                  alignItems: "center", px: 2, py: 1.25, borderRadius: 2,
                  bgcolor: g.place === 1 ? "rgba(212,166,69,0.18)" : "rgba(127,127,127,0.08)",
                  outline: g.mine ? "2px solid rgba(217,23,58,0.5)" : "none",
                }}
              >
                <Typography sx={{ width: 28, fontWeight: 700 }}>{g.place === 1 ? "🏆" : g.place ? `${g.place}.` : ""}</Typography>
                <Typography sx={{ flex: 1, fontWeight: 600 }}>
                  {g.name}
                  {g.mine ? " (you)" : ""}
                </Typography>
                <Typography sx={{ opacity: 0.8 }} suppressHydrationWarning>
                  {when(g.guess)}
                </Typography>
                {g.offBySeconds !== undefined ? (
                  <Typography sx={{ opacity: 0.6, minWidth: 110, textAlign: "right" }}>{offBy(g.offBySeconds)}</Typography>
                ) : null}
              </Stack>
            ))}
          </Stack>
        )}
      </Box>
    </Box>
  );
}
