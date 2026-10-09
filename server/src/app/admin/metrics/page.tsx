import { Box, Paper, Stack, Table, TableBody, TableCell, TableHead, TableRow, Typography } from "@mui/material";
import { headers } from "next/headers";
import { notFound } from "next/navigation";
import type { ReactNode } from "react";
import { metricsAuthorized } from "@/lib/adminAuth.ts";
import type { EventName } from "@/lib/events.ts";
import { cohorts, monthly, newInstalls, sources, sum, totals } from "@/lib/metrics.ts";

export const dynamic = "force-dynamic";
export const metadata = { title: "Metrics · Count Downcula", robots: { index: false } };

const pct = (n: number | null) => (n === null ? "–" : `${Math.round(n * 100)}%`);
const ratio = (a: number, b: number) => (b ? a / b : null);

function Section({ title, note, children }: { title: string; note?: string; children: ReactNode }) {
  return (
    <Paper sx={{ p: 2.5 }}>
      <Typography variant="h6" component="h2">{title}</Typography>
      {note ? <Typography variant="body2" sx={{ opacity: 0.7, mb: 1.5 }}>{note}</Typography> : null}
      <Box sx={{ overflowX: "auto" }}>{children}</Box>
    </Paper>
  );
}

function Tile({ label, value, detail }: { label: string; value: string; detail?: string }) {
  return (
    <Paper sx={{ p: 2.5, flex: 1, minWidth: 200 }}>
      <Typography variant="body2" sx={{ opacity: 0.7 }}>{label}</Typography>
      <Typography sx={{ fontSize: 36, fontWeight: 600, fontVariantNumeric: "tabular-nums" }}>{value}</Typography>
      {detail ? <Typography variant="body2" sx={{ opacity: 0.7 }}>{detail}</Typography> : null}
    </Paper>
  );
}

const FUNNEL: [EventName, string][] = [
  ["page_view", "Live page views"],
  ["clip_launch", "App Clip launches"],
  ["clip_keep_it", "Keep It taps"],
  ["install_from_link", "Installs with a link waiting"],
];

const PARTICIPATION: [EventName, string][] = [
  ["join", "Joins"],
  ["coffin_drop", "Coffin drops"],
  ["pool_guess", "Pool guesses"],
  ["wallet_pass_add", "Wallet passes added"],
];

const PLATFORMS = ["ios", "ipados", "macos", "watchos", "clip", "web", "unknown"];

export default async function MetricsPage() {
  // The proxy asks for the password; this makes sure nothing renders without it.
  if (!metricsAuthorized((await headers()).get("authorization"))) notFound();

  const [months, last30, installs, cohortRows, viewSources, createdHow, paywallWhy] = await Promise.all([
    monthly(),
    totals(30),
    newInstalls(30),
    cohorts(8),
    sources("page_view"),
    sources("countdown_created"),
    sources("paywall_shown"),
  ]);
  const thisMonth = months[0];
  const count = (name: EventName) => sum(last30.get(name));
  const paywalls = count("paywall_shown");
  const purchases = count("purchase_completed");

  return (
    <Box component="main" sx={{ maxWidth: 1100, mx: "auto", px: 2, py: 4 }}>
      <Typography variant="h4" component="h1" sx={{ mb: 0.5 }}>Metrics</Typography>
      <Typography variant="body2" sx={{ opacity: 0.7, mb: 3 }}>
        From the event log. App events come only from builds with Share Analytics on; the last 30 days unless noted.
      </Typography>

      <Stack direction="row" sx={{ gap: 2, flexWrap: "wrap", mb: 2 }}>
        <Tile
          label={`Shared per active install, ${thisMonth.month}`}
          value={thisMonth.sharedPerActive === null ? "–" : thisMonth.sharedPerActive.toFixed(2)}
          detail={`${thisMonth.publishes} shared by ${thisMonth.activeInstalls} active installs`}
        />
        <Tile
          label="New installs from a link"
          value={pct(ratio(installs.fromLink, installs.total))}
          detail={`${installs.fromLink} of ${installs.total} new installs`}
        />
        <Tile
          label="Paywall to purchase"
          value={pct(ratio(purchases, paywalls))}
          detail={`${purchases} purchases from ${paywalls} paywalls`}
        />
      </Stack>

      <Stack sx={{ gap: 2 }}>
        <Section title="The north star by month" note="Countdowns shared (published) per install that sent an active ping that month.">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Month</TableCell>
                <TableCell align="right">Active installs</TableCell>
                <TableCell align="right">Shared</TableCell>
                <TableCell align="right">Joins</TableCell>
                <TableCell align="right">Shared per active</TableCell>
              </TableRow>
            </TableHead>
            <TableBody>
              {months.map((m) => (
                <TableRow key={m.month}>
                  <TableCell>{m.month}</TableCell>
                  <TableCell align="right">{m.activeInstalls}</TableCell>
                  <TableCell align="right">{m.publishes}</TableCell>
                  <TableCell align="right">{m.joins}</TableCell>
                  <TableCell align="right">{m.sharedPerActive === null ? "–" : m.sharedPerActive.toFixed(2)}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Section>

        <Section title="Link funnel" note="Each step as a share of the one before. Counts are events, not people.">
          <Table size="small">
            <TableBody>
              {FUNNEL.map(([name, label], i) => (
                <TableRow key={name}>
                  <TableCell>{label}</TableCell>
                  <TableCell align="right">{count(name)}</TableCell>
                  <TableCell align="right" sx={{ opacity: 0.7 }}>{i ? pct(ratio(count(name), count(FUNNEL[i - 1][0]))) : ""}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Section>

        <Section title="Who takes part, by platform" note="Web is everyone in a browser: Android, desktop, and iPhones without the app.">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell />
                {PLATFORMS.map((p) => <TableCell key={p} align="right">{p}</TableCell>)}
              </TableRow>
            </TableHead>
            <TableBody>
              {PARTICIPATION.map(([name, label]) => (
                <TableRow key={name}>
                  <TableCell>{label}</TableCell>
                  {PLATFORMS.map((p) => <TableCell key={p} align="right">{last30.get(name)?.get(p) ?? 0}</TableCell>)}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Section>

        <Section title="Weekly cohorts" note="Installs by the week they were first seen, and the share active in each week after.">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Week of</TableCell>
                <TableCell align="right">Installs</TableCell>
                {cohortRows[0]?.retained.map((_, i) => <TableCell key={i} align="right">W{i}</TableCell>)}
              </TableRow>
            </TableHead>
            <TableBody>
              {cohortRows.map((c) => (
                <TableRow key={c.week}>
                  <TableCell>{c.week}</TableCell>
                  <TableCell align="right">{c.size}</TableCell>
                  {c.retained.map((r, i) => <TableCell key={i} align="right">{c.size ? pct(r) : "–"}</TableCell>)}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Section>

        <Stack direction={{ xs: "column", md: "row" }} sx={{ gap: 2 }}>
          {[
            { title: "Where page views come from", rows: viewSources, empty: "direct or a chat app" },
            { title: "How countdowns get made", rows: createdHow, empty: "not given" },
            { title: "Why the paywall showed", rows: paywallWhy, empty: "not given" },
          ].map(({ title, rows, empty }) => (
            <Box key={title} sx={{ flex: 1, minWidth: 0 }}>
              <Section title={title}>
                <Table size="small">
                  <TableBody>
                    {rows.length ? rows.map((r) => (
                      <TableRow key={r._id ?? ""}>
                        <TableCell>{r._id ?? empty}</TableCell>
                        <TableCell align="right">{r.n}</TableCell>
                      </TableRow>
                    )) : (
                      <TableRow><TableCell sx={{ opacity: 0.7 }}>Nothing yet</TableCell></TableRow>
                    )}
                  </TableBody>
                </Table>
              </Section>
            </Box>
          ))}
        </Stack>

        <Section title="Every event" note="Totals by platform.">
          <Table size="small">
            <TableHead>
              <TableRow>
                <TableCell>Event</TableCell>
                <TableCell align="right">All</TableCell>
                {PLATFORMS.map((p) => <TableCell key={p} align="right">{p}</TableCell>)}
              </TableRow>
            </TableHead>
            <TableBody>
              {[...last30.entries()].sort((a, b) => sum(b[1]) - sum(a[1])).map(([name, byPlatform]) => (
                <TableRow key={name}>
                  <TableCell>{name}</TableCell>
                  <TableCell align="right">{sum(byPlatform)}</TableCell>
                  {PLATFORMS.map((p) => <TableCell key={p} align="right">{byPlatform.get(p) ?? 0}</TableCell>)}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Section>
      </Stack>
    </Box>
  );
}
