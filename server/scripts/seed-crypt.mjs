// Loads crypt/launch.json into the server's public crypt (creates or updates by slug).
// Usage: BASE=https://go.countdowncula.com CRYPT_ADMIN_TOKEN=... node scripts/seed-crypt.mjs
import { readFileSync } from "node:fs";

const base = process.env.BASE ?? "http://localhost:4300";
const token = process.env.CRYPT_ADMIN_TOKEN;
if (!token) throw new Error("Set CRYPT_ADMIN_TOKEN.");
const entries = JSON.parse(readFileSync(new URL("../crypt/launch.json", import.meta.url), "utf8"));
const res = await fetch(`${base}/api/admin/crypt`, {
  method: "PUT",
  headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
  body: JSON.stringify(entries),
});
console.log(res.status, await res.text());
if (!res.ok) process.exit(1);
