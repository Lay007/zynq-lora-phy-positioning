import numpy as np
import pytest

from zynq_lora_phy import add_awgn, apply_frequency_offset, delay_signal


def test_frequency_offset_rotates_at_requested_rate() -> None:
    offset = 0.125
    result = apply_frequency_offset(np.ones(16), offset)
    phase_step = result[1:] * np.conjugate(result[:-1])

    np.testing.assert_allclose(phase_step, np.exp(2j * np.pi * offset), atol=1e-12)


def test_awgn_has_expected_measured_snr() -> None:
    signal = np.ones(200_000, dtype=np.complex128)
    noisy = add_awgn(signal, snr_db=10.0, rng=np.random.default_rng(4))
    noise = noisy - signal
    measured_snr = 10.0 * np.log10(np.mean(np.abs(signal) ** 2) / np.mean(np.abs(noise) ** 2))

    assert measured_snr == pytest.approx(10.0, abs=0.1)


def test_integer_delay_preserves_signal() -> None:
    signal = np.array([1 + 2j, 3 + 4j])
    delayed = delay_signal(signal, 3)

    np.testing.assert_array_equal(delayed[:3], 0.0)
    np.testing.assert_array_equal(delayed[3:], signal)
