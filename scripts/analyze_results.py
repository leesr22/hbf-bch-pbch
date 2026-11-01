#!/usr/bin/env python3
"""Merge VCS cycles and DC PPA; normalize every passing point to 3.072 TB/s."""

from pathlib import Path
import csv
import math

ROOT = Path(__file__).resolve().parents[1]
TARGET_GBPS = 3072.0
USER_BYTES = 512.0
PBCH_STRESS_DEFECTS = {"pbch_d1": 12, "pbch_d2": 32}
PBCH_MEAN_DEFECTS = {"pbch_d1": 4203e-4, "pbch_d2": 4215e-3}
REDUNDANCY_BITS = {
    "bch_d1": 156,
    "pbch_d1": 107,
    "bch_d2": 364,
    "pbch_d2": 119,
}


def read_csv(name):
    with (ROOT / "results" / name).open() as handle:
        return list(csv.DictReader(handle))


def main():
    cycles = {
        (row["profile"], row["kind"], int(row["width"])): int(row["cycles"])
        for row in read_csv("cycles.csv")
    }
    rows = []
    for synthesis in read_csv("synthesis.csv"):
        if synthesis["result"] != "PASS":
            continue
        key = (synthesis["profile"], synthesis["kind"], int(synthesis["width"]))
        if key not in cycles:
            continue
        measured_cycles = cycles[key]
        effective_cycles = float(measured_cycles)
        if synthesis["kind"] == "enc" and synthesis["profile"].startswith("pbch"):
            effective_cycles += (PBCH_MEAN_DEFECTS[synthesis["profile"]] -
                                 PBCH_STRESS_DEFECTS[synthesis["profile"]])
        frequency = int(synthesis["frequency_mhz"])
        engine_gbps = USER_BYTES * frequency / 1000.0 / effective_cycles
        engines = math.ceil(TARGET_GBPS / engine_gbps)
        area = float(synthesis["area_um2"])
        rows.append({
            "profile": synthesis["profile"],
            "kind": synthesis["kind"],
            "width": int(synthesis["width"]),
            "frequency_mhz": frequency,
            "slack_ns": synthesis["slack_ns"],
            "area_um2": area,
            "nand2_ge": float(synthesis["nand2_ge"]),
            "measured_cycles": measured_cycles,
            "effective_cycles": effective_cycles,
            "engine_gbps": engine_gbps,
            "engines_for_3072_gbps": engines,
            "total_area_mm2": area * engines / 1e6,
            "total_nand2_mge": area / 0.504 * engines / 1e6,
        })
    rows.sort(key=lambda row: (row["profile"], row["kind"], row["total_area_mm2"]))
    out = ROOT / "results" / "normalized.csv"
    if not rows:
        raise SystemExit("no passing synthesis point has a matching VCS cycle result")
    with out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    best = {}
    for row in rows:
        best.setdefault((row["profile"], row["kind"]), row)
    report = [
        "# PPA summary\n",
        "Target throughput is 3,072 GB/s of 4096-bit user payload.  PBCH encoder "
        "cycles are adjusted from the stress vectors to the mean target defect count "
        "(0.4203 for D1 and 4.215 for D2). Decoder cycles use the verified maximum-t "
        "error vectors.\n",
        "| Profile | Block | W | MHz | Area (um2) | NAND2 GE | Cycles | GB/s/engine | Engines | Total mm2 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in best.values():
        report.append(
            "| {profile} | {kind} | {width} | {frequency_mhz} | {area_um2:.1f} | "
            "{nand2_ge:.0f} | "
            "{effective_cycles:.3f} | {engine_gbps:.3f} | {engines_for_3072_gbps} | "
            "{total_area_mm2:.3f} |".format(**row)
        )

    comparison_rows = []
    report.extend([
        "\n## Reliability-matched comparison\n",
        "Positive logic overhead means PBCH occupies more normalized codec area; negative means less.",
        "Storage reduction compares total ECC redundancy bits per 4096-bit user word.\n",
        "| Point | Block | BCH mm2 | PBCH mm2 | PBCH logic overhead | BCH redundancy | PBCH redundancy | Storage reduction |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ])
    for point in ("d1", "d2"):
        bch_name = "bch_" + point
        pbch_name = "pbch_" + point
        block_areas = {}
        for kind in ("enc", "dec"):
            if (bch_name, kind) not in best or (pbch_name, kind) not in best:
                continue
            bch_area = best[(bch_name, kind)]["total_area_mm2"]
            pbch_area = best[(pbch_name, kind)]["total_area_mm2"]
            overhead = 100.0 * (pbch_area / bch_area - 1.0)
            block_areas[kind] = (bch_area, pbch_area)
            comparison_rows.append({
                "point": point.upper(), "block": kind,
                "bch_total_area_mm2": bch_area,
                "pbch_total_area_mm2": pbch_area,
                "pbch_logic_overhead_percent": overhead,
                "bch_redundancy_bits": REDUNDANCY_BITS[bch_name],
                "pbch_redundancy_bits": REDUNDANCY_BITS[pbch_name],
                "storage_reduction_percent": 100.0 * (
                    1.0 - REDUNDANCY_BITS[pbch_name] / REDUNDANCY_BITS[bch_name]),
            })
        if len(block_areas) == 2:
            bch_area = sum(value[0] for value in block_areas.values())
            pbch_area = sum(value[1] for value in block_areas.values())
            comparison_rows.append({
                "point": point.upper(), "block": "enc+dec",
                "bch_total_area_mm2": bch_area,
                "pbch_total_area_mm2": pbch_area,
                "pbch_logic_overhead_percent": 100.0 * (pbch_area / bch_area - 1.0),
                "bch_redundancy_bits": REDUNDANCY_BITS[bch_name],
                "pbch_redundancy_bits": REDUNDANCY_BITS[pbch_name],
                "storage_reduction_percent": 100.0 * (
                    1.0 - REDUNDANCY_BITS[pbch_name] / REDUNDANCY_BITS[bch_name]),
            })
    for row in comparison_rows:
        report.append(
            "| {point} | {block} | {bch_total_area_mm2:.3f} | "
            "{pbch_total_area_mm2:.3f} | {pbch_logic_overhead_percent:+.1f}% | "
            "{bch_redundancy_bits} | {pbch_redundancy_bits} | "
            "{storage_reduction_percent:.1f}% |".format(**row)
        )

    comparison_out = ROOT / "results" / "comparison.csv"
    if comparison_rows:
        with comparison_out.open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=comparison_rows[0].keys(),
                                    lineterminator="\n")
            writer.writeheader()
            writer.writerows(comparison_rows)
    (ROOT / "results" / "summary.md").write_text("\n".join(report) + "\n")
    print("wrote", out, comparison_out, "and results/summary.md")


if __name__ == "__main__":
    main()
