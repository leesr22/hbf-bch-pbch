import random

from model.ecc import FIELD_N, PROFILES, generator_polynomial, lfsr_period


def test_profile_dimensions():
    expected = {
        "bch_d1": (4252, 156),
        "bch_d2": (4460, 364),
        "pbch_d1": (4203, 104),
        "pbch_d2": (4215, 104),
    }
    for name, profile in PROFILES.items():
        if name.startswith("pbch"):
            assert (profile.n, profile.parent.r) == expected[name]
        else:
            assert (profile.n, profile.r) == expected[name]


def test_generator_degrees():
    assert generator_polynomial(8).bit_length() - 1 == 104
    assert generator_polynomial(12).bit_length() - 1 == 156
    assert generator_polynomial(28).bit_length() - 1 == 364


def test_mask_lfsrs_are_maximal():
    assert lfsr_period(3, 0b1011) == 7
    assert lfsr_period(15, 0x8003) == (1 << 15) - 1


def test_bch_encode_decode():
    rng = random.Random(7)
    for name in ("bch_d1", "bch_d2"):
        profile = PROFILES[name]
        message = rng.getrandbits(profile.k)
        word = profile.encode(message)
        assert not any(profile.syndromes(word))
        for weight in (0, 1, profile.t):
            positions = rng.sample(range(profile.n), weight)
            received = word
            for position in positions:
                received ^= 1 << position
            corrected, count, success = profile.decode(received)
            assert success
            assert count == weight
            assert corrected == word


def test_pbch_round_trip_and_masking():
    rng = random.Random(11)
    for name in ("pbch_d1", "pbch_d2"):
        profile = PROFILES[name]
        message = rng.getrandbits(profile.k)
        selector = rng.randrange(1 << profile.l)
        word = profile.encode(message, selector)
        recovered, recovered_selector = profile.recover(word)
        assert recovered == message
        assert recovered_selector == selector
        assert not any(profile.parent.syndromes(word))

        probe = rng.sample(range(profile.n), min(profile.l, 6))
        if profile.l == 3:
            selected, failures = profile.exact_selector(message, probe)
        else:
            selected, failures = profile.greedy_selector(message, probe)
        selected_word = profile.encode(message, selected)
        observed = sum(
            (selected_word >> (profile.n - 1 - position)) & 1 for position in probe
        )
        assert observed == failures

