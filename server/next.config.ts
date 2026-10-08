import type { NextConfig } from "next";

const config: NextConfig = {
  // The preview image route reads its fonts from disk at runtime.
  outputFileTracingIncludes: {
    "/c/[slug]/og": ["./assets/fonts/**"],
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
