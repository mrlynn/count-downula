import { Box, Button, Typography } from "@mui/material";

export default function NotFound() {
  return (
    <Box sx={{ minHeight: "100dvh", display: "grid", placeItems: "center", p: 3, textAlign: "center" }}>
      <Box>
        <Typography variant="h2" component="h1" sx={{ fontSize: { xs: 36, sm: 48 }, mb: 1 }}>
          This countdown has vanished
        </Typography>
        <Typography sx={{ opacity: 0.75, mb: 3 }}>The link may be wrong, or its owner unpublished it.</Typography>
        <Button variant="contained" href="https://www.countdowncula.com">
          Get Count Downcula
        </Button>
      </Box>
    </Box>
  );
}
