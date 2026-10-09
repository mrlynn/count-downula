import { publicOrigin } from "@/lib/http.ts";

/**
 * The one-line embed: `<script async src=".../embed.js" data-countdown="<slug>"></script>`.
 * It puts an iframe of /embed/<slug> right after itself. Optional data-theme (style, dark, light),
 * data-end (message, recap, countup, hide, redirect), data-message, data-redirect (with
 * data-end="redirect", on hosted countdowns), data-width and data-height.
 */
export function GET() {
  const origin = JSON.stringify(publicOrigin());
  const script = `(function () {
  var s = document.currentScript;
  if (!s) return;
  var slug = s.getAttribute("data-countdown") || "";
  if (!/^[A-Za-z0-9-]{4,40}$/.test(slug)) return;
  var q = [];
  ["theme", "end", "message"].forEach(function (k) {
    var v = s.getAttribute("data-" + k);
    if (v) q.push(k + "=" + encodeURIComponent(v));
  });
  var size = function (v, d) { return /^\\d+(px|%|rem|em|vw)?$/.test(v || "") ? (/\\d$/.test(v) ? v + "px" : v) : d; };
  var f = document.createElement("iframe");
  f.src = ${origin} + "/embed/" + slug + (q.length ? "?" + q.join("&") : "");
  f.title = "Countdown";
  f.loading = "lazy";
  f.setAttribute("allowtransparency", "true");
  f.style.cssText = "border:0;display:block;width:100%;max-width:" + size(s.getAttribute("data-width"), "560px") +
    ";height:" + size(s.getAttribute("data-height"), "180px") + ";color-scheme:normal;";
  s.parentNode.insertBefore(f, s.nextSibling);
  // A hosted countdown's embed reports zero; this page then goes where it said, over https only.
  var to = s.getAttribute("data-redirect") || "";
  if (/^https:\/\//.test(to)) {
    window.addEventListener("message", function (e) {
      if (e.origin === ${origin} && e.source === f.contentWindow && e.data && e.data.type === "countdowncula:zero") {
        window.location.assign(to);
      }
    });
  }
})();
`;
  return new Response(script, {
    headers: { "Content-Type": "text/javascript; charset=utf-8", "Cache-Control": "public, max-age=3600, s-maxage=86400" },
  });
}
