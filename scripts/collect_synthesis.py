#!/usr/bin/env python3
"""Collect every completed DC run into one machine-readable table."""

from pathlib import Path
import csv
import re

ROOT = Path(__file__).resolve().parents[1]
PATTERN = re.compile(
    r"^(bch_d[12]|pbch_d[12])_(enc|dec)_w(32|64|128|256|512)_([0-9]+)mhz$"
)


def read_status(path):
    values = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def main():
    rows = []
    for directory in sorted((ROOT / "syn" / "results").iterdir()):
        match = PATTERN.match(directory.name)
        status_file = directory / "status.txt"
        if not match or not status_file.exists():
            continue
        profile, kind, width, frequency = match.groups()
        status = read_status(status_file)
        area = float(status["area_um2"])
        rows.append({
            "profile": profile,
            "kind": kind,
            "width": int(width),
            "frequency_mhz": int(frequency),
            "result": status["result"],
            "slack_ns": float(status["slack_ns"]),
            "area_um2": area,
            "nand2_ge": area / 0.504,
        })
    out = ROOT / "results" / "synthesis.csv"
    out.parent.mkdir(exist_ok=True)
    with out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print("wrote", out, "rows", len(rows))


if __name__ == "__main__":
    main()
