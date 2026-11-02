#!/usr/bin/env python3
"""Generate W=64 PBCH wrappers for selector-length hardware sweeps."""

from argparse import ArgumentParser
from itertools import combinations
from pathlib import Path
import json
import sys

from sympy import factorint

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

from model.ecc import PBCH
from gen_rtl import (
    pbch_decoder_wrapper,
    pbch_encoder_wrapper,
    write_pbch_vectors,
)


def poly_mul_mod(a, b, modulus, degree):
    result = 0
    mask = (1 << degree) - 1
    while b:
        if b & 1:
            result ^= a
        b >>= 1
        a <<= 1
        if a & (1 << degree):
            a ^= modulus
    return result & mask


def poly_pow_mod(value, exponent, modulus, degree):
    result = 1
    while exponent:
        if exponent & 1:
            result = poly_mul_mod(result, value, modulus, degree)
        value = poly_mul_mod(value, value, modulus, degree)
        exponent >>= 1
    return result


def is_primitive(polynomial, degree, prime_factors):
    order = (1 << degree) - 1
    if poly_pow_mod(2, order, polynomial, degree) != 1:
        return False
    return all(
        poly_pow_mod(2, order // factor, polynomial, degree) != 1
        for factor in prime_factors
    )


def sparse_primitive_polynomial(degree):
    """Return the first minimum-weight primitive polynomial found."""
    factors = factorint((1 << degree) - 1)
    for middle_terms in (1, 3, 5):
        for positions in combinations(range(1, degree), middle_terms):
            polynomial = (1 << degree) | 1
            for position in positions:
                polynomial |= 1 << position
            if is_primitive(polynomial, degree, factors):
                return polynomial
    raise RuntimeError("no sparse primitive polynomial found for L=%d" % degree)


def main():
    parser = ArgumentParser()
    parser.add_argument(
        "--lengths",
        default="3,4,5,6,8,10,11,12,13,14,15,24,36,48,52,53,54,55,56,60,64",
        help="comma-separated selector lengths (1..64)",
    )
    args = parser.parse_args()
    lengths = sorted(set(int(value) for value in args.lengths.split(",")))
    if not lengths or lengths[0] < 2 or lengths[-1] > 64:
        raise SystemExit("selector lengths must be in 2..64 for the W=64 sweep")

    wrappers = ["`default_nettype none\n"]
    manifest = {}
    for length in lengths:
        if length == 3:
            primitive, seed = 0xB, 7
        elif length == 15:
            primitive, seed = 0x8003, 0x3341
        else:
            primitive, seed = sparse_primitive_polynomial(length), 1
        profile = PBCH(4096, length, 8, primitive, seed)
        solver_modes = [("gauss", False, False), ("pipe", False, True)]
        if length <= 6:
            solver_modes.insert(0, ("exact", True, False))
        for solver_name, solver_exact, solver_pipelined in solver_modes:
            name = "pbch_l%02d_%s" % (length, solver_name)
            wrappers.append(pbch_encoder_wrapper(
                name, profile, 64, solver_exact, solver_pipelined))
            wrappers.append(pbch_decoder_wrapper(name, profile, 64))
            write_pbch_vectors(name, profile, 64, solver_exact)
        manifest[str(length)] = {
            "primitive": hex(primitive),
            "seed": hex(seed),
            "n": profile.n,
            "r": profile.parent.r,
        }
    wrappers.append("\n`default_nettype wire\n")

    generated = ROOT / "rtl" / "generated"
    generated.mkdir(parents=True, exist_ok=True)
    (generated / "pbch_sweep_wrappers.sv").write_text("".join(wrappers))
    (generated / "pbch_sweep_manifest.json").write_text(
        json.dumps(manifest, indent=2) + "\n"
    )
    print("generated PBCH sweep lengths:", ", ".join(map(str, lengths)))


if __name__ == "__main__":
    main()
