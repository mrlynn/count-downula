import { Box, Button, Typography } from "@mui/material";
import { headers } from "next/headers";
import { pickLocale, t } from "@/lib/i18n.ts";

export default async function NotFound() {
  const locale = pickLocale((await headers()).get("accept-language"));
  return (
    <Box sx={{ minHeight: "100dvh", display: "grid", placeItems: "center", p: 3, textAlign: "center" }}>
      <Box>
        <Typography variant="h2" component="h1" sx={{ fontSize: { xs: 36, sm: 48 }, mb: 1 }}>
          {t(locale, "notFoundTitle")}
        </Typography>
        <Typography sx={{ opacity: 0.75, mb: 3 }}>{t(locale, "notFoundBody")}</Typography>
        <Button variant="contained" href="https://www.countdowncula.com">
          {t(locale, "getCountdowncula")}
        </Button>
      </Box>
    </Box>
  );
}
