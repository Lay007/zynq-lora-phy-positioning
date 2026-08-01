import numpy as np
import pytest

from zynq_lora_phy import (
    CssConfig,
    add_awgn,
    apply_frequency_offset,
    demodulate,
    demodulate_symbol,
    estimate_frequency_offset,
    modulate,
    modulate_symbol,
    reference_chirp,
)


def test_reference_chirp_has_unit_magnitude() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    chirp = reference_chirp(config)

    assert chirp.shape == (256,)
    np.testing.assert_allclose(np.abs(chirp), 1.0, atol=1e-12)
    np.testing.assert_allclose(reference_chirp(config, up=False), np.conjugate(chirp))


@pytest.mark.parametrize("samples_per_chip", [1, 2, 4])
def test_every_sf7_symbol_round_trips(samples_per_chip: int) -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=samples_per_chip)

    recovered = [
        demodulate_symbol(modulate_symbol(symbol, config), config)
        for symbol in range(config.symbol_count)
    ]

    np.testing.assert_array_equal(recovered, np.arange(config.symbol_count))


def test_sequence_survives_noise_and_compensated_cfo() -> None:
    config = CssConfig(spreading_factor=7, samples_per_chip=2)
    symbols = np.array([0, 3, 17, 63, 92, 127])
    cfo = 0.00125
    waveform = apply_frequency_offset(modulate(symbols, config), cfo)
    waveform = add_awgn(waveform, snr_db=10.0, rng=np.random.default_rng(42))

    estimated_cfo = estimate_frequency_offset(
        waveform[: config.samples_per_symbol], config, known_symbol=0
    )
    recovered = demodulate(
        waveform,
        config,
        frequency_offset_cycles_per_sample=estimated_cfo,
    )

    assert estimated_cfo == pytest.approx(cfo, abs=1.0e-4)
    np.testing.assert_array_equal(recovered, symbols)


def test_invalid_css_configuration_and_symbol_are_rejected() -> None:
    with pytest.raises(ValueError):
        CssConfig(spreading_factor=4)
    with pytest.raises(ValueError):
        CssConfig(samples_per_chip=0)

    config = CssConfig()
    with pytest.raises(ValueError):
        modulate_symbol(config.symbol_count, config)
    with pytest.raises(ValueError):
        demodulate(np.zeros(config.samples_per_symbol + 1), config)
