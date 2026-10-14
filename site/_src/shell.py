"""Builds the secondary pages from body fragments so they share one header and footer.
Run: python3 site/_src/shell.py  (writes site/<name>.html)"""
import pathlib, re

HERE = pathlib.Path(__file__).parent
SITE = HERE.parent
index = (SITE / "index.html").read_text()
header = re.search(r'<header class="top".*?</header>', index, re.S).group(0)
header = header.replace('href="#tour"', 'href="/#tour"').replace('href="#try"', 'href="/#try"').replace('href="#iphone"', 'href="/#iphone"').replace('href="#watch"', 'href="/#watch"').replace('href="#together"', 'href="/#together"').replace('href="#install"', 'href="/#install"')
footer = re.search(r'<footer class="foot">.*?</footer>', index, re.S).group(0)

PAGES = {
    "support": ("Support", "Get help with Count Downcula, the countdown app for your Mac menu bar, iPhone and Apple Watch."),
    "privacy": ("Privacy policy", "Count Downcula collects no personal data. Here is exactly what happens with your information."),
    "terms": ("Terms of use", "The terms for using the Count Downcula app and website."),
    "cookies": ("Cookie policy", "The Count Downcula website sets no cookies. Here are the details."),
}

for name, (title, desc) in PAGES.items():
    body = (HERE / f"{name}.html").read_text()
    html = f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}: Count Downcula</title>
<meta name="description" content="{desc}">
<meta name="theme-color" content="#1a0612">
<link rel="canonical" href="https://www.countdowncula.com/{name}">
<link rel="icon" href="/assets/favicon.png" type="image/png">
<link rel="apple-touch-icon" href="/assets/apple-touch-icon.png">
<link rel="stylesheet" href="/assets/site.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>

{header}

<main id="main" class="doc">
<div class="doc-inner">
{body.strip()}
</div>
</main>

{footer}

<script src="/assets/site.js" defer></script>
</body>
</html>
"""
    (SITE / f"{name}.html").write_text(html)
    print("wrote", name)
