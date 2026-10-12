import { Box, Button, Typography } from "@mui/material";
import { headers } from "next/headers";
import { CATEGORIES, listCrypt } from "@/lib/crypt.ts";
import { pickLocale, t, type Key } from "@/lib/i18n.ts";
import { CategoryTabs, CryptList } from "./CryptList.tsx";

export async function CryptPage({ category }: { category?: string }) {
  const entries = await listCrypt(category);
  const locale = pickLocale((await headers()).get("accept-language"));
  // Category names come from the dictionary by slug (holidays, sky, sports, fun).
  const categories = CATEGORIES.map((c) => ({ slug: c.slug, name: t(locale, c.slug as Key) }));
  const name = categories.find((c) => c.slug === category)?.name;
  return (
    <Box component="main" sx={{ maxWidth: 1080, mx: "auto", px: { xs: 2, sm: 4 }, py: { xs: 4, sm: 6 } }}>
      <Typography sx={{ fontFamily: `"Young Serif", Georgia, serif`, fontSize: { xs: 36, sm: 52 }, lineHeight: 1.1 }}>
        {name ? t(locale, "cryptOf", { name }) : t(locale, "crypt")}
      </Typography>
      <Typography sx={{ opacity: 0.75, mt: 1, mb: 3, maxWidth: 640 }}>
        {t(locale, "cryptIntro")}
      </Typography>
      <CategoryTabs categories={categories} current={category} allLabel={t(locale, "all")} />
      <CryptList entries={entries} serverNow={Date.now()} locale={locale} />
      <Box sx={{ mt: 6, display: "flex", gap: 2, alignItems: "center", flexWrap: "wrap" }}>
        <Typography sx={{ opacity: 0.75 }}>{t(locale, "cryptPitch")}</Typography>
        <Button variant="contained" href="https://www.countdowncula.com">{t(locale, "getCountdowncula")}</Button>
      </Box>
    </Box>
  );
}
