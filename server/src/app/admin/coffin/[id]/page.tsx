import { notFound } from "next/navigation";
import { contributions, parseId, reportSignatureValid } from "@/lib/coffin.ts";
import { getCountdown } from "@/lib/countdowns.ts";

export const dynamic = "force-dynamic";
export const metadata = { title: "Review · Count Downcula", robots: { index: false } };

type Props = { params: Promise<{ id: string }>; searchParams: Promise<{ sig?: string; removed?: string }> };

/** Opened from a report email. Shows the contribution and asks before removing it. */
export default async function ReviewPage({ params, searchParams }: Props) {
  const { id } = await params;
  const { sig = "", removed } = await searchParams;
  const _id = parseId(id);
  if (!_id || !reportSignatureValid(id, sig)) notFound();
  const contribution = await (await contributions()).findOne({ _id });
  if (!contribution) notFound();
  const countdown = await getCountdown(contribution.slug);
  const style = { maxWidth: 560, margin: "48px auto", padding: "0 16px", fontFamily: "system-ui, sans-serif", color: "#FAF2E3" };
  return (
    <main style={style}>
      <h1 style={{ fontSize: 24 }}>Reported contribution</h1>
      <p style={{ opacity: 0.7 }}>
        In {countdown ? `“${countdown.title}”` : "a countdown that's no longer shared"} · {contribution.reports} report
        {contribution.reports === 1 ? "" : "s"}
      </p>
      <p><b>From:</b> {contribution.name}</p>
      {contribution.text ? <p style={{ whiteSpace: "pre-wrap" }}>{contribution.text}</p> : null}
      {contribution.photoPath ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={`/api/admin/coffin/${id}/photo?sig=${encodeURIComponent(sig)}`} alt="Reported photo"
             style={{ maxWidth: "100%", borderRadius: 12 }} />
      ) : null}
      {contribution.removedAt || removed ? (
        <p style={{ fontWeight: 600 }}>Removed. Nobody can see it anymore.</p>
      ) : (
        <form method="post" action={`/api/admin/coffin/${id}/remove`}>
          <input type="hidden" name="sig" value={sig} />
          <button type="submit" style={{ padding: "12px 20px", borderRadius: 10, border: 0, background: "#D9173A", color: "white", fontSize: 16 }}>
            Remove it
          </button>
        </form>
      )}
    </main>
  );
}
