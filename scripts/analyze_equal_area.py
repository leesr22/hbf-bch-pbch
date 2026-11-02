#!/usr/bin/env python3
"""Combine ideal-UBER limits with measured 28-nm sweep results."""

from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path

from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parents[1]
TARGET_GBPS = 3072.0
WIDTH = 64
FREQUENCY_MHZ = 250
INFO_BYTES = 512
BASE_II = 71.0
DECODER_II = 69.0


def ideal_limits(workbook: Path, target: float) -> dict[int, float]:
    sheet = load_workbook(workbook, data_only=True, read_only=True)["Ideal_UBER"]
    rows = list(sheet.iter_rows(values_only=True))
    columns = {
        int(value): column
        for column, value in enumerate(rows[0])
        if column >= 3 and isinstance(value, (int, float))
    }
    limits: dict[int, float] = {}
    for length, column in columns.items():
        samples = [
            (float(row[0]), float(row[column]))
            for row in rows[1:]
            if row[0] not in (None, 0) and row[column] not in (None, 0)
        ]
        below = [(p, uber) for p, uber in samples if uber <= target]
        if not below:
            continue
        low_p, low_uber = below[-1]
        higher = [(p, uber) for p, uber in samples if p > low_p]
        if not higher:
            limits[length] = low_p
            continue
        high_p, high_uber = higher[0]
        if high_uber <= target:
            limits[length] = high_p
            continue
        log_target = math.log10(target)
        fraction = ((log_target - math.log10(low_uber)) /
                    (math.log10(high_uber) - math.log10(low_uber)))
        limits[length] = 10 ** (
            math.log10(low_p) + fraction *
            (math.log10(high_p) - math.log10(low_p)))
    return limits


def read_status(path: Path) -> dict[str, str]:
    values = {}
    for line in path.read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    return values


def measured_points() -> list[dict[str, object]]:
    pattern = re.compile(
        r"pbch_l(?P<length>\d+)_(?P<solver>exact|gauss|pipe)_"
        r"(?P<block>enc|dec)_w64_250mhz"
    )
    points = []
    for status_path in (ROOT / "syn" / "results").glob("pbch_l*/status.txt"):
        match = pattern.fullmatch(status_path.parent.name)
        if not match:
            continue
        status = read_status(status_path)
        points.append({
            "length": int(match.group("length")),
            "solver": match.group("solver"),
            "block": match.group("block"),
            "result": status.get("result", ""),
            "slack_ns": float(status.get("slack_ns", "nan")),
            "area_um2": float(status.get("area_um2", "nan")),
        })
    return points


def encoder_ii(length: int, solver: str, mean_constraints: float) -> float:
    if solver == "exact":
        return BASE_II + mean_constraints
    if solver == "gauss":
        return BASE_II + length + mean_constraints
    if solver == "pipe":
        return BASE_II + length + math.ceil(length / 2) + mean_constraints
    raise ValueError(solver)


def engines_for_ii(ii: float) -> int:
    throughput = INFO_BYTES * FREQUENCY_MHZ / 1000.0 / ii
    return math.ceil(TARGET_GBPS / throughput)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("workbook", type=Path)
    parser.add_argument("--target", type=float, default=1e-17)
    parser.add_argument(
        "--output", type=Path,
        default=ROOT / "results" / "equal_area_measured.csv")
    args = parser.parse_args()

    limits = ideal_limits(args.workbook, args.target)
    points = measured_points()
    decoder_area = {
        int(point["length"]): float(point["area_um2"])
        for point in points
        if point["block"] == "dec" and point["result"] == "PASS"
    }
    rows = []
    for point in points:
        if point["block"] != "enc" or point["result"] != "PASS":
            continue
        length = int(point["length"])
        if length not in limits or length not in decoder_area:
            continue
        p_limit = limits[length]
        n = 4096 + 104 + length
        mean_constraints = n * p_limit
        solver = str(point["solver"])
        enc_ii = encoder_ii(length, solver, mean_constraints)
        enc_engines = engines_for_ii(enc_ii)
        dec_engines = engines_for_ii(DECODER_II)
        enc_total = float(point["area_um2"]) * enc_engines / 1e6
        dec_total = decoder_area[length] * dec_engines / 1e6
        rows.append({
            "l": length,
            "solver": solver,
            "max_ber_defect": p_limit,
            "reliability_defects_per_codeword_2np": 2 * n * p_limit,
            "hardware_mean_constraints_np": mean_constraints,
            "encoder_ii_cycles": enc_ii,
            "encoder_area_um2": float(point["area_um2"]),
            "encoder_engines": enc_engines,
            "encoder_total_mm2": enc_total,
            "decoder_area_um2": decoder_area[length],
            "decoder_engines": dec_engines,
            "decoder_total_mm2": dec_total,
            "combined_total_mm2": enc_total + dec_total,
            "encoder_slack_ns": float(point["slack_ns"]),
        })
    rows.sort(key=lambda row: (int(row["l"]), str(row["solver"])))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]) if rows else [])
        if rows:
            writer.writeheader()
            writer.writerows(rows)
    for row in rows:
        print(
            "l={l:>3} {solver:<5} p={max_ber_defect:.4g} "
            "enc={encoder_total_mm2:7.2f} dec={decoder_total_mm2:7.2f} "
            "total={combined_total_mm2:7.2f} mm2".format(**row))


if __name__ == "__main__":
    main()
