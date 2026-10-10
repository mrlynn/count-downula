#!/usr/bin/env python3
"""Measures docs/app-store-listing-localized.md against App Store Connect's limits."""
import re
import sys
from pathlib import Path

LIMITS = {"Subtitle": 30, "Promotional text": 170, "Keywords": 100, "Description": 4000}
text = Path(__file__).resolve().parent.parent.joinpath("docs/app-store-listing-localized.md").read_text()
failed = False
for section in re.split(r"\n## ", text)[1:]:
    language = section.splitlines()[0]
    fields = dict(re.findall(r"### ([^\n]+)\n\n(.*?)(?=\n### |\n---|\Z)", section, flags=re.S))
    for field, limit in LIMITS.items():
        body = fields.get(field, "").strip().strip("`").strip()
        body = re.sub(r"^> ", "", body)
        size = len(body)
        flag = "OK" if size <= limit else "TOO LONG"
        failed |= size > limit
        print(f"{language:28} {field:18} {size:5}/{limit:<5} {flag}")

# What's New for each release (docs/whats-new-*.md): every fenced block is one platform's text.
for notes in sorted(Path(__file__).resolve().parent.parent.joinpath("docs").glob("whats-new-*.md")):
    body = notes.read_text()
    for section in re.split(r"\n## ", body)[1:]:
        language = section.splitlines()[0]
        for platform, block in re.findall(r"### ([^\n]+)\n\n```\n(.*?)\n```", section, flags=re.S):
            size, limit = len(block), 4000
            failed |= size > limit
            print(f"{notes.stem:14} {language[:22]:22} {platform[:28]:28} {size:5}/{limit:<5} {'OK' if size <= limit else 'TOO LONG'}")
sys.exit(1 if failed else 0)
