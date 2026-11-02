#!/usr/bin/env python3
"""Normalize the common W=64, 250-MHz pipelined codecs to HBF bandwidth."""

from pathlib import Path
import csv
import math

ROOT = Path(__file__).resolve().parents[1]
TARGET_GBPS = 3072.0
USER_BYTES = 512.0
WIDTH = 64
FREQUENCY_MHZ = 250
PBCH_STRESS_DEFECTS = {"pbch_d1": 12, "pbch_d2": 32}
PBCH_MEAN_DEFECTS = {"pbch_d1": 4203e-4, "pbch_d2": 4215e-3}
REDUNDANCY = {"bch_d1": 156, "pbch_d1": 107,
              "bch_d2": 364, "pbch_d2": 119}


def read_csv(name):
    with (ROOT / "results" / name).open() as handle:
        return list(csv.DictReader(handle))


def main():
    cycles = {
        (row["profile"], row["kind"]): row
        for row in read_csv("pipeline_cycles.csv")
        if int(row["width"]) == WIDTH
    }
    synthesis = {
        (row["profile"], row["kind"]): row
        for row in read_csv("synthesis.csv")
        if int(row["width"]) == WIDTH and
           int(row["frequency_mhz"]) == FREQUENCY_MHZ and
           row["result"] == "PASS"
    }
    rows = []
    for profile in ("bch_d1", "pbch_d1", "bch_d2", "pbch_d2"):
        for kind in ("enc", "dec"):
            key = (profile, kind)
            if key not in cycles or key not in synthesis:
                raise SystemExit(f"missing common pipeline point {key}")
            latency = int(cycles[key]["latency_cycles"])
            measured_ii = int(cycles[key]["ii_cycles"])
            effective_ii = float(measured_ii)
            if kind == "enc" and profile.startswith("pbch"):
                effective_ii += PBCH_MEAN_DEFECTS[profile] - PBCH_STRESS_DEFECTS[profile]
            engine_gbps = USER_BYTES * FREQUENCY_MHZ / 1000.0 / effective_ii
            engines = math.ceil(TARGET_GBPS / engine_gbps)
            area = float(synthesis[key]["area_um2"])
            rows.append({
                "profile": profile,
                "kind": kind,
                "width": WIDTH,
                "frequency_mhz": FREQUENCY_MHZ,
                "slack_ns": float(synthesis[key]["slack_ns"]),
                "area_um2": area,
                "nand2_ge": area / 0.504,
                "latency_cycles": latency,
                "measured_ii_cycles": measured_ii,
                "effective_ii_cycles": effective_ii,
                "engine_gbps": engine_gbps,
                "engines_for_3072_gbps": engines,
                "total_area_mm2": area * engines / 1e6,
            })

    out = ROOT / "results" / "pipeline_common_w64_250mhz.csv"
    with out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)

    by_key = {(row["profile"], row["kind"]): row for row in rows}
    comparisons = []
    for point in ("d1", "d2"):
        bch, pbch = "bch_"+point, "pbch_"+point
        for kind in ("enc", "dec"):
            ba = by_key[(bch, kind)]["total_area_mm2"]
            pa = by_key[(pbch, kind)]["total_area_mm2"]
            comparisons.append({
                "point": point.upper(), "block": kind,
                "bch_total_area_mm2": ba, "pbch_total_area_mm2": pa,
                "pbch_change_percent": 100.0*(pa/ba-1.0),
                "storage_reduction_percent": 100.0*(1.0-REDUNDANCY[pbch]/REDUNDANCY[bch]),
            })
        ba = sum(by_key[(bch, k)]["total_area_mm2"] for k in ("enc", "dec"))
        pa = sum(by_key[(pbch, k)]["total_area_mm2"] for k in ("enc", "dec"))
        comparisons.append({
            "point": point.upper(), "block": "enc+dec",
            "bch_total_area_mm2": ba, "pbch_total_area_mm2": pa,
            "pbch_change_percent": 100.0*(pa/ba-1.0),
            "storage_reduction_percent": 100.0*(1.0-REDUNDANCY[pbch]/REDUNDANCY[bch]),
        })
    cmp_out = ROOT / "results" / "pipeline_comparison.csv"
    with cmp_out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=comparisons[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(comparisons)

    baseline = read_csv("bch_d2_single_bm_baseline.csv")[0]
    dual = by_key[("bch_d2", "dec")]
    bm_rows = []
    for architecture, area, ii in (
        ("single_bm", float(baseline["area_um2"]), float(baseline["ii_cycles"])),
        ("dual_bm", dual["area_um2"], dual["effective_ii_cycles"]),
    ):
        engine_gbps = USER_BYTES * FREQUENCY_MHZ / 1000.0 / ii
        engines = math.ceil(TARGET_GBPS / engine_gbps)
        bm_rows.append({
            "architecture": architecture,
            "area_um2": area,
            "ii_cycles": ii,
            "engine_gbps": engine_gbps,
            "engines_for_3072_gbps": engines,
            "total_area_mm2": area * engines / 1e6,
        })
    bm_out = ROOT / "results" / "pipeline_bch_d2_bm_comparison.csv"
    with bm_out.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=bm_rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(bm_rows)

    report = [
        "# Common W=64, 250-MHz pipeline result\n",
        "Throughput uses steady-state initiation interval, not end-to-end latency. "
        "PBCH encoder II is adjusted from the stress vector to the target mean defect count.\n",
        "| Profile | Block | Area (um2) | Latency | II | GB/s/engine | Engines | Total mm2 |",
        "|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        report.append(
            "| {profile} | {kind} | {area_um2:.1f} | {latency_cycles} | "
            "{effective_ii_cycles:.3f} | {engine_gbps:.3f} | "
            "{engines_for_3072_gbps} | {total_area_mm2:.3f} |".format(**row)
        )
    report.extend([
        "\n## Reliability-matched comparison\n",
        "| Point | Block | BCH mm2 | PBCH mm2 | PBCH change | Storage reduction |",
        "|---|---:|---:|---:|---:|---:|",
    ])
    for row in comparisons:
        report.append(
            "| {point} | {block} | {bch_total_area_mm2:.3f} | "
            "{pbch_total_area_mm2:.3f} | {pbch_change_percent:+.1f}% | "
            "{storage_reduction_percent:.1f}% |".format(**row)
        )
    report.extend([
        "\n## BCH-D2 BM resource balancing\n",
        "| Architecture | Area (um2) | II | GB/s/engine | Engines | Total mm2 |",
        "|---|---:|---:|---:|---:|---:|",
    ])
    for row in bm_rows:
        report.append(
            "| {architecture} | {area_um2:.1f} | {ii_cycles:.0f} | "
            "{engine_gbps:.3f} | {engines_for_3072_gbps} | "
            "{total_area_mm2:.3f} |".format(**row)
        )
    (ROOT / "results" / "pipeline_summary.md").write_text("\n".join(report)+"\n")
    print("wrote", out, cmp_out, bm_out, "and results/pipeline_summary.md")


if __name__ == "__main__":
    main()
