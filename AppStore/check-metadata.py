#!/usr/bin/env python3
"""Checks the App Store text in AppStore/metadata.md against Apple's character limits.

Usage: python3 AppStore/check-metadata.py
"""
import pathlib
import re
import sys

LIMITS = {"name": 30, "subtitle": 30}
text = (pathlib.Path(__file__).parent / "metadata.md").read_text()
ok = True

# Fenced fields: <!-- field: name (max N) --> followed by a ``` block.
for name, limit, body in re.findall(r"<!-- field: (\w+) \(max (\d+)\) -->\s*```\n(.*?)\n```", text, re.S):
    n = len(body)
    status = "ok" if n <= int(limit) else "TOO LONG"
    ok &= n <= int(limit)
    print(f"{name:12} {n:5} / {limit:<5} {status}")
    if name == "keywords" and ", " in body:
        print("             keywords should have no spaces after commas")
        ok = False

# Table fields.
for field, limit in LIMITS.items():
    m = re.search(rf"^\| {field.capitalize()} \| (.+?) \|$", text, re.M)
    if m:
        n = len(m.group(1))
        ok &= n <= limit
        print(f"{field:12} {n:5} / {limit:<5} {'ok' if n <= limit else 'TOO LONG'}")

sys.exit(0 if ok else 1)
