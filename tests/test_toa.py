import numpy as np
import pytest

from zynq_lora_phy import CssConfig, add_awgn, delay_signal, estimate_toa, modulate


def test_matched_filter_recovers_integer_delay() -> None:
    reference = modulate([0, 0, 0], CssConfig(spreading_factor=7))
    received = delay_signal(reference, 37)
    received = np.pad(received, (0, 19))

    estimate = estimate_toa(received, reference)

    assert estimate.sample_index == pytest.approx(37.0, abs=1e-12)
    assert estimate.peak_magnitude == pytest.approx(reference.size, rel=1e-12)


def test_matched_filter_is_stable_with_noise() -> None:
    reference = modulate([0, 0, 0, 0], CssConfig(spreading_factor=7))
    received = delay_signal(reference, 21)
    received = np.pad(received, (0, 20))
    received = add_awgn(received, snr_db=0.0, rng=np.random.default_rng(8))

    estimate = estimate_toa(received, reference)

    assert estimate.sample_index == pytest.approx(21.0, abs=0.25)


def test_invalid_toa_inputs_are_rejected() -> None:
    with pytest.raises(ValueError):
        estimate_toa(np.ones(4), np.ones(5))
    with pytest.raises(ValueError):
        estimate_toa(np.ones(5), np.zeros(3))
