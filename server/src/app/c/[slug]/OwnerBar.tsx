"use client";

import { Box, Button, Stack, Typography } from "@mui/material";
import { useEffect, useState } from "react";
import { EmailEditLink } from "@/app/new/EmailEditLink.tsx";
import { ownedTokens } from "@/app/new/Editor.tsx";
import { t, type Locale } from "@/lib/i18n.ts";

/** On the live page, for the browser that made the countdown on the web: edit it, or email a link to. */
export function OwnerBar({ slug, locale, emailEnabled }: { slug: string; locale: Locale; emailEnabled: boolean }) {
  const [token, setToken] = useState<string | null>(null);
  const [emailing, setEmailing] = useState(false);
  useEffect(() => setToken(ownedTokens()[slug] ?? null), [slug]);
  if (!token) return null;
  return (
    <Box sx={{ bgcolor: "background.paper", borderBottom: "1px solid", borderColor: "divider", px: { xs: 2, sm: 4 }, py: 1.5 }}>
      <Stack direction={{ xs: "column", sm: "row" }} spacing={1.5} sx={{ maxWidth: 960, mx: "auto", alignItems: { sm: "center" } }}>
        <Typography variant="body2" sx={{ flex: 1, opacity: 0.85 }}>{t(locale, "youMadeThis")}</Typography>
        <Stack direction="row" spacing={1}>
          <Button size="small" variant="outlined" href={`/c/${slug}/edit`}>{t(locale, "edit")}</Button>
          {emailEnabled ? (
            <Button size="small" onClick={() => setEmailing((v) => !v)}>{t(locale, "emailLinkTitle")}</Button>
          ) : null}
        </Stack>
      </Stack>
      {emailing ? (
        <Box sx={{ maxWidth: 960, mx: "auto", mt: 1.5 }}>
          <EmailEditLink slug={slug} token={token} locale={locale} />
        </Box>
      ) : null}
    </Box>
  );
}
