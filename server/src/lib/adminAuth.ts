import { timingSafeEqual } from "node:crypto";

/**
 * HTTP Basic auth for /admin/metrics: any user name, `METRICS_PASSWORD` as the password (at least
 * 16 characters). Without it set, the dashboard stays shut.
 */
export function metricsAuthorized(header: string | null, password = process.env.METRICS_PASSWORD ?? ""): boolean {
  if (password.length < 16) return false;
  const match = /^Basic\s+(.+)$/i.exec(header ?? "");
  if (!match) return false;
  const decoded = Buffer.from(match[1], "base64").toString("utf8");
  const given = Buffer.from(decoded.slice(decoded.indexOf(":") + 1));
  const expected = Buffer.from(password);
  return given.length === expected.length && timingSafeEqual(given, expected);
}
