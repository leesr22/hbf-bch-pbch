"""Reference BCH/PBCH model used to generate and check RTL.

Polynomial bit i is the coefficient of x**i.  Codewords are transferred from the
highest polynomial degree to the lowest.  The shortened code omits leading zero
message coefficients from the primitive BCH(8191, *) mother code.
"""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Iterable, Sequence


M = 13
FIELD_N = (1 << M) - 1
PRIMITIVE_POLY = 0x201B  # x^13 + x^4 + x^3 + x + 1


def parity(value: int) -> int:
    # The lab's default Python is older than int.bit_count().
    return bin(value).count("1") & 1


def gf_mul(a: int, b: int, m: int = M, primitive: int = PRIMITIVE_POLY) -> int:
    result = 0
    mask = (1 << m) - 1
    while b:
        if b & 1:
            result ^= a
        b >>= 1
        a <<= 1
        if a & (1 << m):
            a ^= primitive
    return result & mask


def gf_pow(a: int, exponent: int) -> int:
    if exponent < 0:
        return gf_pow(gf_inv(a), -exponent)
    result = 1
    while exponent:
        if exponent & 1:
            result = gf_mul(result, a)
        a = gf_mul(a, a)
        exponent >>= 1
    return result


def gf_inv(a: int) -> int:
    if not a:
        raise ZeroDivisionError("zero has no multiplicative inverse")
    return gf_pow(a, FIELD_N - 1)


def cyclotomic_coset(start: int) -> tuple[int, ...]:
    values: list[int] = []
    value = start % FIELD_N
    while value not in values:
        values.append(value)
        value = (value * 2) % FIELD_N
    return tuple(values)


def gf_poly_mul(a: Sequence[int], b: Sequence[int]) -> list[int]:
    result = [0] * (len(a) + len(b) - 1)
    for i, av in enumerate(a):
        for j, bv in enumerate(b):
            result[i + j] ^= gf_mul(av, bv)
    return result


@lru_cache(maxsize=None)
def minimal_polynomial(coset: tuple[int, ...]) -> int:
    coefficients = [1]
    for exponent in coset:
        coefficients = gf_poly_mul(coefficients, [gf_pow(2, exponent), 1])
    result = 0
    for degree, coefficient in enumerate(coefficients):
        if coefficient not in (0, 1):
            raise AssertionError("minimal polynomial did not reduce to GF(2)")
        result |= coefficient << degree
    return result


def binary_poly_mul(a: int, b: int) -> int:
    result = 0
    while b:
        if b & 1:
            result ^= a
        a <<= 1
        b >>= 1
    return result


@lru_cache(maxsize=None)
def generator_polynomial(t: int) -> int:
    seen: set[int] = set()
    result = 1
    for root in range(1, 2 * t + 1):
        coset = cyclotomic_coset(root)
        leader = min(coset)
        if leader in seen:
            continue
        seen.add(leader)
        result = binary_poly_mul(result, minimal_polynomial(coset))
    return result


@dataclass(frozen=True)
class BCH:
    k: int
    t: int

    @property
    def generator(self) -> int:
        return generator_polynomial(self.t)

    @property
    def r(self) -> int:
        return self.generator.bit_length() - 1

    @property
    def n(self) -> int:
        return self.k + self.r

    def encode(self, message: int) -> int:
        if message < 0 or message >= (1 << self.k):
            raise ValueError("message does not fit profile")
        dividend = message << self.r
        remainder = dividend
        for degree in range(self.n - 1, self.r - 1, -1):
            if (remainder >> degree) & 1:
                remainder ^= self.generator << (degree - self.r)
        return dividend | (remainder & ((1 << self.r) - 1))

    def syndromes(self, word: int) -> list[int]:
        values = []
        set_positions = [i for i in range(self.n) if (word >> i) & 1]
        for root in range(1, 2 * self.t + 1):
            value = 0
            for position in set_positions:
                value ^= gf_pow(2, (root * position) % FIELD_N)
            values.append(value)
        return values

    def decode(self, received: int) -> tuple[int, int, bool]:
        """Return corrected word, number of roots, and success flag."""
        synd = self.syndromes(received)
        if not any(synd):
            return received, 0, True

        sigma = [0] * (2 * self.t + 1)
        previous = [0] * (2 * self.t + 1)
        sigma[0] = 1
        previous[0] = 1
        degree = 0
        shift = 1
        scale = 1

        for iteration in range(2 * self.t):
            discrepancy = synd[iteration]
            for j in range(1, degree + 1):
                discrepancy ^= gf_mul(sigma[j], synd[iteration - j])
            if discrepancy == 0:
                shift += 1
                continue
            saved = sigma.copy()
            factor = gf_mul(discrepancy, gf_inv(scale))
            for j in range(0, 2 * self.t + 1 - shift):
                if previous[j]:
                    sigma[j + shift] ^= gf_mul(factor, previous[j])
            if 2 * degree <= iteration:
                degree = iteration + 1 - degree
                previous = saved
                scale = discrepancy
                shift = 1
            else:
                shift += 1

        error_positions: list[int] = []
        for position in range(self.n):
            x = gf_pow(2, (-position) % FIELD_N)
            value = 0
            power = 1
            for coefficient in sigma[: degree + 1]:
                value ^= gf_mul(coefficient, power)
                power = gf_mul(power, x)
            if value == 0:
                error_positions.append(position)

        corrected = received
        for position in error_positions:
            corrected ^= 1 << position
        success = len(error_positions) == degree and not any(self.syndromes(corrected))
        return corrected, len(error_positions), success


def lfsr_step(state: int, width: int, primitive: int) -> int:
    carry = (state >> (width - 1)) & 1
    state = (state << 1) & ((1 << width) - 1)
    if carry:
        state ^= primitive & ((1 << width) - 1)
    return state


def lfsr_period(width: int, primitive: int) -> int:
    state = 1
    count = 0
    while True:
        state = lfsr_step(state, width, primitive)
        count += 1
        if state == 1 or state == 0:
            return count


@dataclass(frozen=True)
class PBCH:
    k: int
    l: int
    t: int = 8
    mask_primitive: int = 0
    mask_seed: int = 1

    @property
    def parent(self) -> BCH:
        return BCH(self.k + self.l, self.t)

    @property
    def n(self) -> int:
        return self.parent.n

    def mask_columns(self) -> list[int]:
        state = self.mask_seed
        columns = []
        for _ in range(self.k):
            columns.append(state)
            state = lfsr_step(state, self.l, self.mask_primitive)
        return columns

    @lru_cache(maxsize=None)
    def influence_columns(self) -> tuple[int, ...]:
        """Selector signature at every final-codeword stream position."""
        mask_columns = self.mask_columns()
        basis_words = []
        for bit in range(self.l):
            payload_mask = 0
            for stream_position, column in enumerate(mask_columns):
                if (column >> bit) & 1:
                    payload_mask |= 1 << (self.k - 1 - stream_position)
            information = ((1 << bit) << self.k) | payload_mask
            basis_words.append(self.parent.encode(information))

        columns = []
        for stream_position in range(self.n):
            polynomial_position = self.n - 1 - stream_position
            signature = 0
            for bit, word in enumerate(basis_words):
                signature |= ((word >> polynomial_position) & 1) << bit
            columns.append(signature)
        return tuple(columns)

    def encode(self, message: int, selector: int) -> int:
        if selector < 0 or selector >= (1 << self.l):
            raise ValueError("selector does not fit profile")
        masked_message = message
        for stream_position, column in enumerate(self.mask_columns()):
            if parity(selector & column):
                masked_message ^= 1 << (self.k - 1 - stream_position)
        information = (selector << self.k) | masked_message
        return self.parent.encode(information)

    def recover(self, corrected_word: int) -> tuple[int, int]:
        information = corrected_word >> self.parent.r
        selector = information >> self.k
        masked_message = information & ((1 << self.k) - 1)
        message = masked_message
        for stream_position, column in enumerate(self.mask_columns()):
            if parity(selector & column):
                message ^= 1 << (self.k - 1 - stream_position)
        return message, selector

    def base_word(self, message: int) -> int:
        return self.encode(message, 0)

    def exact_selector(self, message: int, probe_positions: Iterable[int]) -> tuple[int, int]:
        base = self.base_word(message)
        positions = tuple(probe_positions)
        signatures = self.influence_columns()
        best_selector = 0
        best_failures = len(positions) + 1
        for selector in range(1 << self.l):
            failures = 0
            for stream_position in positions:
                base_bit = (base >> (self.n - 1 - stream_position)) & 1
                failures += base_bit ^ parity(selector & signatures[stream_position])
            if failures < best_failures:
                best_selector = selector
                best_failures = failures
                if failures == 0:
                    break
        return best_selector, best_failures

    def greedy_selector(self, message: int, probe_positions: Iterable[int]) -> tuple[int, int]:
        base = self.base_word(message)
        signatures = self.influence_columns()
        pivots = [0] * self.l
        valid = [False] * self.l
        conflicts = 0

        for stream_position in probe_positions:
            rhs = (base >> (self.n - 1 - stream_position)) & 1
            row = signatures[stream_position] | (rhs << self.l)
            stored = False
            for pivot in range(self.l - 1, -1, -1):
                if not ((row >> pivot) & 1):
                    continue
                if valid[pivot]:
                    row ^= pivots[pivot]
                else:
                    pivots[pivot] = row
                    valid[pivot] = True
                    stored = True
                    break
            if not stored and (row & ((1 << self.l) - 1)) == 0:
                conflicts += (row >> self.l) & 1

        selector = 0
        for pivot in range(self.l):
            if not valid[pivot]:
                continue
            rhs = (pivots[pivot] >> self.l) & 1
            lower = pivots[pivot] & ((1 << pivot) - 1)
            bit = rhs ^ parity(lower & selector)
            selector |= bit << pivot
        return selector, conflicts


PROFILES = {
    "bch_d1": BCH(4096, 12),
    "bch_d2": BCH(4096, 28),
    # Seeds avoid zero/duplicate influence columns as far as possible within
    # the compact LFSR mask family (quality is reported by gen_constants.py).
    "pbch_d1": PBCH(4096, 3, 8, 0b1011, 7),
    # The degree-15 primitive polynomial is selected by scripts/gen_constants.py.
    "pbch_d2": PBCH(4096, 15, 8, 0x8003, 0x3341),
}
