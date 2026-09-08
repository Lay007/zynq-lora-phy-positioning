"""Checks for the shared CSS FFT-correlator stage decomposition.

The Python implementation mirrors the authoritative MATLAB
``lora_phy.fft_correlator_stages``.  These tests hold it to the two properties
that make it usable as a differential reference: its aliasing shortcut is the
exact full-length correlation, and its decisions agree with the independent
sample-wise dechirp demodulator.
"""

import numpy as np
import pytest

from zynq_lora_phy import (
    CssConfig,
    demodulate_symbol,
    fft_correlator_stages,
    modulate_symbol,
    reference_chirp,
)


@pytest.mark.parametrize("samples_per_chip", [1, 2, 8])
def test_stage_decisions_match_the_dechirp_demodulator(samples_per_chip: int) -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=samples_per_chip)
    windows = np.stack(
        [modulate_symbol(symbol, config) for symbol in range(config.symbol_count)]
    )
    stages = fft_correlator_stages(windows, config)
    expected = [
        demodulate_symbol(window, config) for window in windows
    ]
    assert list(stages.symbols) == expected
    assert list(stages.symbols) == list(range(config.symbol_count))


@pytest.mark.parametrize("spreading_factor", [5, 7, 9])
def test_aliasing_shortcut_equals_the_full_length_correlation(
    spreading_factor: int,
) -> None:
    config = CssConfig(spreading_factor=spreading_factor, samples_per_chip=4)
    size = config.samples_per_symbol
    rng = np.random.default_rng(spreading_factor)
    noise = rng.standard_normal(size) + 1j * rng.standard_normal(size)
    window = modulate_symbol(3, config) + 0.3 * noise

    stages = fft_correlator_stages(window, config)
    full = np.fft.ifft(stages.product[0])
    lags = (-np.arange(config.symbol_count) * config.samples_per_chip) % size
    assert np.allclose(stages.fft_n[0], full[lags], atol=1e-9)


def test_stage_shapes_follow_the_documented_widths() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    windows = np.stack([modulate_symbol(symbol, config) for symbol in (0, 64, 127)])
    stages = fft_correlator_stages(windows, config)
    assert stages.windows.shape == (3, config.samples_per_symbol)
    assert stages.fft_m.shape == (3, config.samples_per_symbol)
    assert stages.product.shape == (3, config.samples_per_symbol)
    assert stages.partition.shape == (3, config.symbol_count)
    assert stages.fft_n.shape == (3, config.symbol_count)
    assert stages.magnitude_squared.shape == (3, config.symbol_count)
    assert stages.symbols.shape == (3,)


def test_a_single_window_is_accepted_without_stacking() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    stages = fft_correlator_stages(modulate_symbol(19, config), config)
    assert stages.symbols.shape == (1,)
    assert int(stages.symbols[0]) == 19


def test_peak_and_runner_up_are_ordered_and_distinct() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    windows = np.stack([modulate_symbol(symbol, config) for symbol in (0, 40, 127)])
    stages = fft_correlator_stages(windows, config)
    assert np.all(stages.peak_power >= stages.second_power)
    assert np.all(stages.symbols != stages.second_symbols)
    assert np.all(stages.confidence > 0.5)


def test_confidence_is_the_peak_share_of_total_power() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    stages = fft_correlator_stages(modulate_symbol(11, config), config)
    total = stages.magnitude_squared.sum(axis=1)
    assert np.allclose(stages.confidence, stages.peak_power / total)


def test_an_explicit_downchirp_reference_detects_a_downchirp() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=4)
    downchirp = reference_chirp(config, up=False)
    stages = fft_correlator_stages(downchirp, config, reference=downchirp)
    assert int(stages.symbols[0]) == 0


def test_a_wrongly_sized_window_is_rejected() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    with pytest.raises(ValueError, match="samples"):
        fft_correlator_stages(np.zeros(17, dtype=complex), config)


def test_a_wrongly_sized_reference_is_rejected() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    window = modulate_symbol(0, config)
    with pytest.raises(ValueError, match="reference"):
        fft_correlator_stages(window, config, reference=np.zeros(5, dtype=complex))


def test_a_zero_energy_reference_is_rejected() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    window = modulate_symbol(0, config)
    zeros = np.zeros(config.samples_per_symbol, dtype=complex)
    with pytest.raises(ValueError, match="non-zero energy"):
        fft_correlator_stages(window, config, reference=zeros)
