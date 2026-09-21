import importlib.util
import json
from pathlib import Path

import numpy as np
import pytest

from zynq_lora_phy.fm_positioning import (
    FmWaveformConfig,
    ambiguity_peak,
    autocorrelation_metrics,
    delay_crlb_std_s,
    make_lfm_waveform,
    make_sinusoidal_nlfm_waveform,
    optimize_harmonic_fm,
    rms_bandwidth_hz,
)


ROOT = Path(__file__).resolve().parents[1]
RUNNER_SPEC = importlib.util.spec_from_file_location(
    "run_fm_positioning_experiment",
    ROOT / "tools" / "run_fm_positioning_experiment.py",
)
assert RUNNER_SPEC is not None and RUNNER_SPEC.loader is not None
RUNNER = importlib.util.module_from_spec(RUNNER_SPEC)
RUNNER_SPEC.loader.exec_module(RUNNER)


def test_equal_duration_bandwidth_and_energy_waveforms() -> None:
    config = FmWaveformConfig()
    lfm = make_lfm_waveform(config)
    nlfm = make_sinusoidal_nlfm_waveform(config)

    for waveform in (lfm, nlfm):
        assert waveform.samples.size == config.sample_count
        assert np.vdot(waveform.samples, waveform.samples).real == pytest.approx(
            config.energy, rel=1e-12
        )
        assert waveform.instantaneous_frequency_hz[0] == pytest.approx(
            -config.bandwidth_hz / 2.0
        )
        assert waveform.instantaneous_frequency_hz[-1] == pytest.approx(
            config.bandwidth_hz / 2.0
        )
        assert np.all(np.diff(waveform.instantaneous_frequency_hz) > 0.0)


def test_edge_dwelling_nlfm_increases_rms_bandwidth() -> None:
    config = FmWaveformConfig()
    lfm = make_lfm_waveform(config)
    nlfm = make_sinusoidal_nlfm_waveform(config)

    assert rms_bandwidth_hz(lfm) == pytest.approx(
        config.bandwidth_hz / np.sqrt(12.0), rel=2e-3
    )
    assert rms_bandwidth_hz(nlfm) > 1.2 * rms_bandwidth_hz(lfm)
    assert delay_crlb_std_s(nlfm, 20.0) < delay_crlb_std_s(lfm, 20.0)


def test_autocorrelation_and_ambiguity_metrics_are_resolved() -> None:
    config = FmWaveformConfig()
    waveform = make_lfm_waveform(config)
    metrics = autocorrelation_metrics(waveform, config.sample_rate_hz)
    negative = ambiguity_peak(waveform, config.sample_rate_hz, -100.0)
    positive = ambiguity_peak(waveform, config.sample_rate_hz, 100.0)

    assert 8 <= metrics.mainlobe_width_samples <= 24
    assert metrics.peak_sidelobe_db < -10.0
    assert metrics.integrated_sidelobe_db < 0.0
    assert negative.delay_samples == pytest.approx(-positive.delay_samples, abs=1e-9)
    assert negative.normalized_magnitude == pytest.approx(
        positive.normalized_magnitude, rel=1e-12
    )


def test_optimizer_is_deterministic_and_keeps_a_monotone_non_lfm_law() -> None:
    config = FmWaveformConfig(sample_rate_hz=250_000.0, duration_s=1.024e-3)
    search_first = np.array([0.0, 0.08, 0.16])
    search_second = np.array([-0.02, 0.0, 0.02])

    first = optimize_harmonic_fm(
        config,
        first_harmonics=search_first,
        second_harmonics=search_second,
        design_doppler_hz=100.0,
    )
    second = optimize_harmonic_fm(
        config,
        first_harmonics=search_first,
        second_harmonics=search_second,
        design_doppler_hz=100.0,
    )

    assert first.score < 1.0
    assert first.waveform.harmonic_coefficients != (0.0, 0.0)
    assert first.waveform.harmonic_coefficients == second.waveform.harmonic_coefficients
    assert first.score == pytest.approx(second.score, abs=1e-15)
    assert np.all(np.diff(first.waveform.instantaneous_frequency_hz) > 0.0)


def test_experiment_runner_writes_self_describing_tables(tmp_path: Path) -> None:
    report = RUNNER.run_experiment(
        tmp_path, trials=2, seed=17, snr_values_db=[20.0]
    )

    assert {row["waveform"] for row in report["metrics"]} == {
        "lfm",
        "sinusoidal_nlfm",
        "optimized_fm",
    }
    assert report["optimization"]["selected_harmonic_coefficients"] != [0.0, 0.0]
    assert (tmp_path / "waveform-metrics.csv").is_file()
    assert (tmp_path / "ambiguity-cuts.csv").is_file()
    assert (tmp_path / "monte-carlo-toa.csv").is_file()
    persisted = json.loads((tmp_path / "summary.json").read_text(encoding="utf-8"))
    assert persisted["configuration"]["monte_carlo_seed"] == 17
    assert persisted["files"]["waveform_metrics"] == "waveform-metrics.csv"
