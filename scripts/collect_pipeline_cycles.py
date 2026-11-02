#!/usr/bin/env python3
"""Collect multi-frame latency and steady-state initiation intervals."""

from pathlib import Path
import csv
import re

ROOT = Path(__file__).resolve().parents[1]
METRIC = re.compile(r"METRIC (encoder|decoder)_(latency|ii)=([0-9]+)")


def main():
    rows = []
    for profile in ("bch_d1", "bch_d2", "pbch_d1", "pbch_d2"):
        for width in (32, 64, 128, 256, 512):
            log = ROOT / "build" / f"vcs_{profile}_pipeline_w{width}" / "run.log"
            if not log.exists() or "PASS" not in log.read_text():
                continue
            metrics = {(block, metric): int(value)
                       for block, metric, value in METRIC.findall(log.read_text())}
            if len(metrics) != 4:
                continue
            for block in ("encoder", "decoder"):
                rows.append({
                    "profile": profile,
                    "kind": "enc" if block == "encoder" else "dec",
                    "width": width,
                    "latency_cycles": metrics[(block, "latency")],
                    "ii_cycles": metrics[(block, "ii")],
                })
    if not rows:
        raise SystemExit("no passing pipeline logs found")
    out = ROOT / "results" / "pipeline_cycles.csv"
    with out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print("wrote", out, "rows", len(rows))


if __name__ == "__main__":
    main()
