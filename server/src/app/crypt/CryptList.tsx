"use client";

import { Box, Button, Card, CardActionArea, Chip, Stack, Typography } from "@mui/material";
import { useEffect, useState } from "react";
import type { CryptEntry } from "@/lib/crypt.ts";
import { t, type Locale } from "@/lib/i18n.ts";
import { webStyle } from "@/lib/style.ts";
import { compact, viewerTarget } from "@/lib/time.ts";

/** The crypt's cards, each ticking on the viewer's own clock. */
export function CryptList({ entries, serverNow, locale = "en" }: { entries: CryptEntry[]; serverNow: number; locale?: Locale }) {
  const [now, setNow] = useState(() => new Date(serverNow));
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    setMounted(true);
    setNow(new Date());
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  if (entries.length === 0) {
    return <Typography sx={{ opacity: 0.7 }}>{t(locale, "cryptEmpty")}</Typography>;
  }
  return (
    <Box sx={{ display: "grid", gap: 2, gridTemplateColumns: { xs: "1fr", sm: "1fr 1fr", md: "1fr 1fr 1fr" } }}>
      {entries.map(({ countdown, memberCount }) => {
        const style = webStyle(countdown.style, false);
        const target = countdown.floating && !mounted ? new Date(countdown.targetDate) : viewerTarget(countdown);
        const when = mounted
          ? target.toLocaleString(undefined, countdown.floating && countdown.floating.endsWith("T00:00:00")
            ? { weekday: "short", month: "short", day: "numeric", year: "numeric" }
            : { weekday: "short", month: "short", day: "numeric", year: "numeric", hour: "numeric", minute: "2-digit" })
          : "";
        return (
          <Card key={countdown.slug} sx={{ background: style.background, color: style.text, borderRadius: 4 }}>
            <CardActionArea href={`/c/${countdown.slug}`} sx={{ p: 2.5, minHeight: 190, display: "flex", flexDirection: "column", alignItems: "flex-start", justifyContent: "flex-end",
              background: "linear-gradient(180deg, rgba(10,3,6,0) 0%, rgba(10,3,6,0.7) 100%)" }}>
              <Typography sx={{ fontFamily: `"Young Serif", Georgia, serif`, fontSize: 22, lineHeight: 1.15 }}>
                {countdown.title}
              </Typography>
              <Typography sx={{ fontSize: 32, fontWeight: 700, fontVariantNumeric: "tabular-nums" }} suppressHydrationWarning>
                {mounted ? compact(now, target) : " "}
              </Typography>
              <Typography sx={{ opacity: 0.8, fontSize: 14 }} suppressHydrationWarning>
                {when}
                {countdown.floating ? " · your time" : ""}
              </Typography>
              {memberCount > 0 ? (
                <Chip size="small" label={t(locale, "counting", { n: memberCount })}
                      sx={{ mt: 1, bgcolor: "rgba(0,0,0,0.35)", color: "inherit" }} />
              ) : null}
            </CardActionArea>
          </Card>
        );
      })}
    </Box>
  );
}

export function CategoryTabs({ categories, current, allLabel = "All" }: {
  categories: readonly { slug: string; name: string }[];
  current?: string;
  allLabel?: string;
}) {
  return (
    <Stack direction="row" spacing={1} sx={{ flexWrap: "wrap", rowGap: 1, mb: 3 }}>
      <Button size="small" variant={current ? "outlined" : "contained"} href="/crypt">{allLabel}</Button>
      {categories.map((c) => (
        <Button key={c.slug} size="small" variant={current === c.slug ? "contained" : "outlined"} href={`/crypt/${c.slug}`}>
          {c.name}
        </Button>
      ))}
    </Stack>
  );
}
