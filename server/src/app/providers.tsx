"use client";

import { CssBaseline, ThemeProvider, createTheme } from "@mui/material";
import { AppRouterCacheProvider } from "@mui/material-nextjs/v16-appRouter";
import type { ReactNode } from "react";

const theme = createTheme({
  palette: {
    mode: "dark",
    primary: { main: "#D91733" },
    background: { default: "#0F0508", paper: "#1A0A10" },
    text: { primary: "#FAF2E3" },
  },
  shape: { borderRadius: 14 },
  typography: {
    fontFamily: `"Instrument Sans", system-ui, -apple-system, sans-serif`,
    h1: { fontFamily: `"Young Serif", Georgia, serif` },
    h2: { fontFamily: `"Young Serif", Georgia, serif` },
    button: { textTransform: "none", fontWeight: 600 },
  },
});

export function Providers({ children }: { children: ReactNode }) {
  return (
    <AppRouterCacheProvider>
      <ThemeProvider theme={theme}>
        <CssBaseline />
        {children}
      </ThemeProvider>
    </AppRouterCacheProvider>
  );
}
