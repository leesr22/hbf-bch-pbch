#!/usr/bin/env python3
"""Compare the compact L=15 online solver with exhaustive optimum scoring."""

from pathlib import Path
import csv
import random
import sys

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from model.ecc import PROFILES, parity


def greedy_constraints(columns, rhs, width):
    pivots = [0] * width
    valid = [False] * width
    conflicts = 0
    for h, bit in zip(columns, rhs):
        row = h | (bit << width)
        stored = False
        for pivot in range(width - 1, -1, -1):
            if not ((row >> pivot) & 1):
                continue
            if valid[pivot]:
                row ^= pivots[pivot]
            else:
                pivots[pivot] = row
                valid[pivot] = True
                stored = True
                break
        if not stored and (row & ((1 << width) - 1)) == 0:
            conflicts += (row >> width) & 1
    selector = 0
    for pivot in range(width):
        if valid[pivot]:
            bit = ((pivots[pivot] >> width) & 1) ^ parity(
                (pivots[pivot] & ((1 << pivot) - 1)) & selector
            )
            selector |= bit << pivot
    actual = sum(parity(selector & h) != bit for h, bit in zip(columns, rhs))
    assert actual == conflicts
    return conflicts


def main():
    profile = PROFILES["pbch_d2"]
    influence = profile.influence_columns()
    candidates = np.arange(1 << profile.l, dtype=np.uint16)
    parity_table = np.fromiter(
        (parity(value) for value in range(1 << profile.l)),
        dtype=np.uint8,
        count=1 << profile.l,
    )
    rng = random.Random(1508)
    trials = 200
    rows = []
    for defects in (1, 4, 8, 15, 20, 32, 64):
        greedy_total = 0
        optimum_total = 0
        greedy_optimal = 0
        zero_optimum = 0
        for _ in range(trials):
            positions = rng.sample(range(profile.n), defects)
            columns = [influence[p] for p in positions]
            rhs = [rng.getrandbits(1) for _ in positions]
            greedy = greedy_constraints(columns, rhs, profile.l)
            scores = np.zeros(1 << profile.l, dtype=np.uint16)
            for h, bit in zip(columns, rhs):
                scores += parity_table[np.bitwise_and(candidates, h)] != bit
            optimum = int(scores.min())
            greedy_total += greedy
            optimum_total += optimum
            greedy_optimal += greedy == optimum
            zero_optimum += optimum == 0
        rows.append({
            "defects": defects,
            "trials": trials,
            "greedy_mean_failures": greedy_total / trials,
            "optimum_mean_failures": optimum_total / trials,
            "greedy_optimal_fraction": greedy_optimal / trials,
            "fully_maskable_fraction": zero_optimum / trials,
        })

    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    with (out / "solver_quality.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=rows[0].keys(), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    for row in rows:
        print(row)


if __name__ == "__main__":
    main()
