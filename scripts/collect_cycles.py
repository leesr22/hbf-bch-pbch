#!/usr/bin/env python3
"""Collect VCS cycle metrics emitted by the profile testbenches."""

from pathlib import Path
import csv
import re

ROOT = Path(__file__).resolve().parents[1]
DIR_PATTERN = re.compile(r"^vcs_(bch_d[12]|pbch_d[12])_w(32|64|128|256|512)$")
METRIC_PATTERN = re.compile(r"METRIC (encoder|decoder)_cycles=([0-9]+)")


def main():
    rows = []
    for directory in sorted((ROOT / "build").glob("vcs_*_w*")):
        match = DIR_PATTERN.match(directory.name)
        run_log = directory / "run.log"
        if not match or not run_log.exists():
            continue
        metrics = dict((kind, int(value)) for kind, value in
                       METRIC_PATTERN.findall(run_log.read_text()))
        for kind in ("encoder", "decoder"):
            if kind in metrics:
                rows.append({
                    "profile": match.group(1),
                    "kind": "enc" if kind == "encoder" else "dec",
                    "width": int(match.group(2)),
                    "cycles": metrics[kind],
                })
    out = ROOT / "results" / "cycles.csv"
    with out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle,
                                fieldnames=("profile", "kind", "width", "cycles"),
                                lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print("wrote", out, "rows", len(rows))


if __name__ == "__main__":
    main()
