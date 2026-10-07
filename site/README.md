# countdownula.com

Static marketing site. No build step, no dependencies, no cookies, no third-party requests.

| Path | What |
|---|---|
| `index.html` | Home page |
| `support.html`, `privacy.html`, `terms.html`, `cookies.html` | Generated from `_src/*.html` |
| `assets/site.css`, `assets/site.js` | Shared styles and behaviour |
| `assets/fonts/` | Self-hosted Young Serif and Instrument Sans (SIL OFL) |
| `vercel.json` | Clean URLs, security headers, `/download` redirect |

After editing a page body in `_src/`, or the header/footer in `index.html`, rebuild the secondary pages:

```bash
python3 site/_src/shell.py
```

Preview locally (clean URLs like `/support` only work on Vercel; use `/support.html` here):

```bash
python3 -m http.server 4173 --directory site
```

## Deploy

The Vercel project `countdownula` is connected to this GitHub repo with Root Directory `site`:

- Every push to `main` deploys to production.
- Other branches and pull requests get preview deployments.

Domains: `www.countdownula.com` (primary) and `countdownula.com` (redirects to `www` through the domain settings in Vercel).

For a manual deploy from the CLI, run it from the repo root, not from `site/`, because the project's Root Directory is already `site`:

```bash
vercel link --yes --project countdownula   # once, at the repo root
vercel deploy --prod
```

If you change the inline script in `index.html`, update its `sha256` hash in the `Content-Security-Policy` header in `vercel.json`.

`assets/og.png` is rendered from `_src/og.html` with headless Chrome:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars --window-size=1200,630 --screenshot="$PWD/site/assets/og.png" "file://$PWD/site/_src/og.html"
```
