import numpy as np
import pytest

from zynq_lora_phy import (
    CssConfig,
    add_awgn,
    apply_frequency_offset,
    delay_signal,
    estimate_joint_chirp_timing,
    estimate_toa,
    modulate,
    reference_chirp,
)


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


@pytest.mark.parametrize("timing", [-7, -2, 0, 3, 9])
@pytest.mark.parametrize("cfo_bins", [-5.0, -0.5, 0.0, 2.5, 5.0])
def test_joint_up_down_estimate_separates_timing_from_cfo(
    timing: int, cfo_bins: float
) -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    size = config.samples_per_symbol
    up_start = 200
    down_start = 1600
    received = np.zeros(3000, dtype=np.complex128)
    received[up_start + timing : up_start + timing + size] = reference_chirp(config)
    received[down_start + timing : down_start + timing + size] = reference_chirp(
        config, up=False
    )
    received = apply_frequency_offset(received, cfo_bins / size)

    estimate = estimate_joint_chirp_timing(
        received,
        up_start,
        down_start,
        config,
        search_radius=64,
    )

    assert estimate.timing_offset_samples == pytest.approx(timing, abs=0.03)
    assert estimate.correction_samples == timing


def test_joint_chirp_timing_rejects_out_of_capture_search() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=8)

    with pytest.raises(ValueError, match="outside received"):
        estimate_joint_chirp_timing(
            np.ones(2048), 0, 1024, config, search_radius=8
        )
