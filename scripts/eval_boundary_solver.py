#!/usr/bin/env python3
"""Monte-Carlo check of online Gaussian masking at equal-area boundaries."""

from __future__ import annotations

import csv
import json
import random
import sys
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from model.ecc import PBCH


def greedy_failures(columns: list[int], rhs: list[int], length: int) -> int:
    pivots = [0] * length
    valid = [False] * length
    failures = 0
    for column, bit in zip(columns, rhs):
        row = column | (bit << length)
        stored = False
        for pivot in range(length - 1, -1, -1):
            if not ((row >> pivot) & 1):
                continue
            if valid[pivot]:
                row ^= pivots[pivot]
            else:
                pivots[pivot] = row
                valid[pivot] = True
                stored = True
                break
        if not stored and row == (1 << length):
            failures += 1
    return failures


def main() -> None:
    manifest = json.loads(
        (ROOT / "rtl" / "generated" / "pbch_sweep_manifest.json").read_text())
    cases = ((11, 7.378195207278585e-4), (55, 3.42123237e-3))
    trials = 10_000
    py_rng = random.Random(0xE0A1)
    np_rng = np.random.default_rng(0xE0A1)
    rows = []
    for length, ber_defect in cases:
        entry = manifest[str(length)]
        profile = PBCH(
            4096, length, 8, int(entry["primitive"], 16),
            int(entry["seed"], 16))
        signatures = profile.influence_columns()
        # The reliability workbook uses 2*n*p physical defects per codeword.
        mean_defects = 2 * profile.n * ber_defect
        failed_trials = 0
        failure_sum = 0
        max_failures = 0
        exact_failure_sum = 0
        greedy_optimal_trials = 0
        if length <= 15:
            candidates = np.arange(1 << length, dtype=np.uint16)
            parity_table = np.fromiter(
                (bin(value).count("1") & 1 for value in range(1 << length)),
                dtype=np.uint8, count=1 << length)
        else:
            candidates = None
            parity_table = None
        for defects in np_rng.poisson(mean_defects, size=trials):
            count = min(int(defects), profile.n)
            positions = py_rng.sample(range(profile.n), count)
            rhs = [py_rng.getrandbits(1) for _ in positions]
            failures = greedy_failures(
                [signatures[position] for position in positions], rhs, length)
            failed_trials += failures != 0
            failure_sum += failures
            max_failures = max(max_failures, failures)
            if candidates is not None and parity_table is not None:
                scores = np.zeros(1 << length, dtype=np.uint16)
                for position, bit in zip(positions, rhs):
                    scores += parity_table[
                        np.bitwise_and(candidates, signatures[position])
                    ] != bit
                optimum = int(scores.min())
                exact_failure_sum += optimum
                greedy_optimal_trials += failures == optimum
        rows.append({
            "l": length,
            "ber_defect": ber_defect,
            "mean_physical_defects_2np": mean_defects,
            "trials": trials,
            "trials_with_unmasked_constraints": failed_trials,
            "observed_failure_probability": failed_trials / trials,
            "mean_unmasked_constraints": failure_sum / trials,
            "max_unmasked_constraints": max_failures,
            "exact_mean_unmasked_constraints": (
                exact_failure_sum / trials if candidates is not None else ""),
            "greedy_optimal_fraction": (
                greedy_optimal_trials / trials if candidates is not None else ""),
        })
    output = ROOT / "results" / "equal_area_solver_quality.csv"
    with output.open("w", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    for row in rows:
        print(row)


if __name__ == "__main__":
    main()
