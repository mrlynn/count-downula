// Report emails through Resend, using your own Resend account's API key (RESEND_API_KEY).
// REPORT_TO is where reports go; without it, or the key, reports are only counted.
// With no verified domain, Resend only lets onboarding@resend.dev send to the account's own email,
// so REPORT_TO must be that address. With a verified domain, set REPORT_FROM to an address on it.

export interface ReportEmail {
  countdownTitle: string;
  from: string;
  text: string;
  hasPhoto: boolean;
  reports: number;
  reviewURL: string;
}

export async function sendReportEmail(report: ReportEmail, env = process.env): Promise<boolean> {
  if (!env.RESEND_API_KEY || !env.REPORT_TO) return false;
  const escape = (s: string) => s.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]!);
  const html = `
    <p>A contribution in the sealed coffin of <b>${escape(report.countdownTitle)}</b> was reported
    (${report.reports} report${report.reports === 1 ? "" : "s"} so far).</p>
    <p><b>From:</b> ${escape(report.from)}<br><b>Note:</b> ${escape(report.text || "(none)")}<br>
    <b>Photo:</b> ${report.hasPhoto ? "yes" : "no"}</p>
    <p><a href="${escape(report.reviewURL)}">Review and remove it</a></p>`;
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${env.RESEND_API_KEY}`, "content-type": "application/json" },
    body: JSON.stringify({
      from: env.REPORT_FROM ?? "Count Downcula <onboarding@resend.dev>",
      to: [env.REPORT_TO],
      subject: `Reported in the coffin: ${report.countdownTitle}`,
      html,
    }),
  });
  // Shows up in Vercel's function logs, so a misconfigured sender doesn't fail silently.
  if (!response.ok) console.error(`Report email failed (${response.status}): ${await response.text()}`);
  return response.ok;
}
