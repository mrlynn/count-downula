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
sys.exit(1 if failed else 0)
