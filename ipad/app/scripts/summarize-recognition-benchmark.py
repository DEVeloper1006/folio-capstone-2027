#!/usr/bin/env python3
"""Summarize copied, user-reviewed recognition cases; no symbolic equivalence claim."""
import argparse
import json
from pathlib import Path
import statistics

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("directory", type=Path)
args = parser.parse_args()
rows = []
for path in args.directory.glob("*/result.json"):
    record = json.loads(path.read_text())
    if record.get("source") == "user-reviewed":
        rows.append(record)
if not rows:
    raise SystemExit("No user-reviewed cases yet; generated smoke cases are excluded.")
for provider in sorted({row["provider"] for row in rows}):
    selected = [row for row in rows if row["provider"] == provider]
    times = [row["recognitionMilliseconds"] / 1000 for row in selected]
    exact = sum(row["predictedLatex"].strip() == row["expectedLatex"].strip() for row in selected)
    print(json.dumps({"provider": provider, "cases": len(selected), "literal_latex_matches": exact,
        "median_recognition_seconds": statistics.median(times), "min_recognition_seconds": min(times),
        "max_recognition_seconds": max(times), "warning": "User-reviewed convenience sample; not a held-out accuracy benchmark. Timings exclude UI presentation."}, indent=2))
