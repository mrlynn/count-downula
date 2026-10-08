import type { NextConfig } from "next";

const config: NextConfig = {
  // Routes that draw images read their fonts, icon and scene backdrops from disk at runtime.
  outputFileTracingIncludes: {
    "/c/[slug]/og": ["./assets/**", "./public/scenes/**"],
    "/c/[slug]/pass": ["./assets/**", "./public/scenes/**"],
    "/api/wallet/v1/passes/[passType]/[serial]": ["./assets/**", "./public/scenes/**"],
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
        ],
      },
    ];
  },
};

export default config;
