"use client";

import { Alert, Box, Button, Stack, TextField, Typography } from "@mui/material";
import { useState } from "react";
import { t, type Locale } from "@/lib/i18n.ts";
import { looksLikeEmail } from "@/lib/webCreate.ts";

/** "Email me an edit link": so a web-made countdown can be edited from another browser or device. */
export function EmailEditLink({ slug, token, locale }: { slug: string; token: string; locale: Locale }) {
  const [email, setEmail] = useState("");
  const [state, setState] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [message, setMessage] = useState<string | null>(null);

  async function send() {
    if (!looksLikeEmail(email)) return;
    setState("sending");
    const response = await fetch(`/api/countdowns/${slug}/edit-link`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ email }),
    }).catch(() => null);
    if (response?.ok) return setState("sent");
    setMessage((await response?.json().catch(() => null))?.error ?? t(locale, "errGeneric"));
    setState("error");
  }

  return (
    <Box sx={{ p: 2, borderRadius: 3, border: "1px solid", borderColor: "divider" }}>
      <Typography variant="subtitle2">{t(locale, "emailLinkTitle")}</Typography>
      <Typography variant="body2" sx={{ opacity: 0.75, mb: 1.5 }}>{t(locale, "emailLinkBody")}</Typography>
      {state === "sent" ? (
        <Alert severity="success">{t(locale, "sent")}</Alert>
      ) : (
        <Stack direction="row" spacing={1}>
          <TextField size="small" type="email" placeholder={t(locale, "emailPlaceholder")} value={email}
                     onChange={(e) => setEmail(e.target.value)} fullWidth />
          <Button variant="outlined" disabled={!looksLikeEmail(email) || state === "sending"} onClick={send}>
            {t(locale, "send")}
          </Button>
        </Stack>
      )}
      {state === "error" && message ? <Alert severity="error" sx={{ mt: 1 }}>{message}</Alert> : null}
    </Box>
  );
}
