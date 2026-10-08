import { Box, Button, Typography } from "@mui/material";
import { CATEGORIES, listCrypt } from "@/lib/crypt.ts";
import { CategoryTabs, CryptList } from "./CryptList.tsx";

export async function CryptPage({ category }: { category?: string }) {
  const entries = await listCrypt(category);
  const name = CATEGORIES.find((c) => c.slug === category)?.name;
  return (
    <Box component="main" sx={{ maxWidth: 1080, mx: "auto", px: { xs: 2, sm: 4 }, py: { xs: 4, sm: 6 } }}>
      <Typography sx={{ fontFamily: `"Young Serif", Georgia, serif`, fontSize: { xs: 36, sm: 52 }, lineHeight: 1.1 }}>
        {name ? `The Crypt: ${name}` : "The Crypt"}
      </Typography>
      <Typography sx={{ opacity: 0.75, mt: 1, mb: 3, maxWidth: 640 }}>
        Countdowns worth waiting for. Pick one to count down with everyone else; holidays tick to midnight wherever you are.
      </Typography>
      <CategoryTabs categories={CATEGORIES} current={category} />
      <CryptList entries={entries} serverNow={Date.now()} />
      <Box sx={{ mt: 6, display: "flex", gap: 2, alignItems: "center", flexWrap: "wrap" }}>
        <Typography sx={{ opacity: 0.75 }}>Put them on your Lock Screen, watch and menu bar.</Typography>
        <Button variant="contained" href="https://www.countdowncula.com">Get Count Downcula</Button>
      </Box>
    </Box>
  );
}
