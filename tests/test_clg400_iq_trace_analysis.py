import json
from pathlib import Path

import numpy as np

from tools.analyze_clg400_iq_trace import (
    decode_with_adjustment,
    fft_correlator_bins,
)
from zynq_lora_phy import CssConfig, modulate, reference_chirp


GOLDEN = (
    Path(__file__).parents[1]
    / "model"
    / "matlab"
    / "golden"
    / "lora-phy-sf7-cr1.json"
)

REALIGNED_TRACE = (
    Path(__file__).parents[1]
    / "docs"
    / "data"
    / "clg400-grid-resync-2026-09-04.json"
)


def test_two_fft_identity_returns_the_modulated_symbols() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    expected = np.asarray([0, 1, 17, 63, 127])
    waveform = modulate(expected, config)
    starts = np.arange(expected.size) * config.samples_per_symbol

    actual = fft_correlator_bins(waveform, starts, config)

    assert np.array_equal(actual, expected)


def test_two_fft_identity_is_the_frequency_domain_correlation() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    rng = np.random.default_rng(41)
    window = rng.normal(size=config.samples_per_symbol) + 1j * rng.normal(
        size=config.samples_per_symbol
    )

    actual = int(fft_correlator_bins(window, [0], config)[0])

    reference = reference_chirp(config)
    direct = np.asarray(
        [abs(np.vdot(np.roll(reference, -index * 8), window)) ** 2 for index in range(128)]
    )
    assert actual == int(np.argmax(direct))


def test_crc_selects_a_bounded_constant_bin_adjustment() -> None:
    vector = json.loads(GOLDEN.read_text(encoding="utf-8"))
    shifted = [(int(value) - 12) % 128 for value in vector["cssSymbols"]]

    candidate = decode_with_adjustment(shifted, 7, range(-16, 17), None)

    assert candidate is not None
    assert candidate.bin_adjustment == 12
    assert candidate.header_valid
    assert candidate.crc_valid
    assert candidate.payload_hex == bytes(vector["payload"]).hex()


def test_transmitter_sequence_is_part_of_capture_acceptance() -> None:
    evidence = json.loads(REALIGNED_TRACE.read_text(encoding="utf-8"))
    attempt = evidence["accepted_attempt"]
    raw = [int(entry["symbol"]) for entry in attempt["entries"]][1:]
    transmitted = int(attempt["serial"]["tx_sequence"])

    matching = decode_with_adjustment(raw, 7, [0], transmitted)
    mismatching = decode_with_adjustment(raw, 7, [0], transmitted + 1)

    assert matching is not None
    assert matching.crc_valid
    assert matching.transmitter_sequence_matches
    assert mismatching is None
