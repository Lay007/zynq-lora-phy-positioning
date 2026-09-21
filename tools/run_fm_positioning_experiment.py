#!/usr/bin/env python3
"""Compare equal-resource LFM, NLFM, and optimized FM positioning pulses."""

from __future__ import annotations

import argparse
import csv
import json
import subprocess
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import numpy as np

from zynq_lora_phy.fm_positioning import (
    SPEED_OF_LIGHT_M_S,
    FmWaveform,
    FmWaveformConfig,
    ambiguity_peak,
    autocorrelation_metrics,
    delay_crlb_std_s,
    make_lfm_waveform,
    make_sinusoidal_nlfm_waveform,
    monte_carlo_toa,
    optimize_harmonic_fm,
    rms_bandwidth_hz,
)


ROOT = Path(__file__).resolve().parents[1]


def _git_provenance() -> dict[str, Any]:
    def git(*arguments: str) -> str:
        result = subprocess.run(
            ["git", *arguments],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        return result.stdout.strip()

    try:
        commit = git("rev-parse", "HEAD")
        branch = git("branch", "--show-current")
        dirty = bool(git("status", "--porcelain"))
    except (OSError, subprocess.CalledProcessError):
        commit, branch, dirty = "unavailable", "unavailable", None
    return {"commit": commit, "branch": branch, "dirty": dirty}


def _metric_row(
    waveform: FmWaveform,
    config: FmWaveformConfig,
    *,
    crlb_snr_db: float,
    mobile_doppler_hz: float,
) -> dict[str, Any]:
    energy = float(np.vdot(waveform.samples, waveform.samples).real)
    rms_bandwidth = rms_bandwidth_hz(waveform)
    crlb_s = delay_crlb_std_s(waveform, crlb_snr_db)
    correlation = autocorrelation_metrics(waveform, config.sample_rate_hz)
    mobile_peak = ambiguity_peak(
        waveform, config.sample_rate_hz, mobile_doppler_hz
    )
    return {
        "waveform": waveform.name,
        "harmonic_coefficients": ";".join(
            f"{value:.12g}" for value in waveform.harmonic_coefficients
        ),
        "duration_us": 1e6 * waveform.samples.size / config.sample_rate_hz,
        "swept_bandwidth_hz": float(
            waveform.instantaneous_frequency_hz[-1]
            - waveform.instantaneous_frequency_hz[0]
        ),
        "energy": energy,
        "rms_bandwidth_hz": rms_bandwidth,
        "delay_crlb_snr_db": crlb_snr_db,
        "delay_crlb_std_ns": 1e9 * crlb_s,
        "one_way_crlb_std_m": SPEED_OF_LIGHT_M_S * crlb_s,
        "mainlobe_width_samples": correlation.mainlobe_width_samples,
        "mainlobe_width_us": 1e6 * correlation.mainlobe_width_s,
        "peak_sidelobe_db": correlation.peak_sidelobe_db,
        "integrated_sidelobe_db": correlation.integrated_sidelobe_db,
        "mobile_doppler_hz": mobile_doppler_hz,
        "mobile_peak_delay_samples": mobile_peak.delay_samples,
        "mobile_peak_bias_m": (
            SPEED_OF_LIGHT_M_S
            * mobile_peak.delay_samples
            / config.sample_rate_hz
        ),
        "mobile_peak_loss_db": 20.0
        * np.log10(max(mobile_peak.normalized_magnitude, np.finfo(float).tiny)),
    }


def _ambiguity_rows(
    waveforms: list[FmWaveform],
    config: FmWaveformConfig,
    dopplers_hz: list[float],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for waveform in waveforms:
        for doppler_hz in dopplers_hz:
            peak = ambiguity_peak(waveform, config.sample_rate_hz, doppler_hz)
            rows.append(
                {
                    "waveform": waveform.name,
                    "doppler_hz": peak.doppler_hz,
                    "peak_delay_samples": peak.delay_samples,
                    "peak_delay_us": 1e6
                    * peak.delay_samples
                    / config.sample_rate_hz,
                    "one_way_bias_m": SPEED_OF_LIGHT_M_S
                    * peak.delay_samples
                    / config.sample_rate_hz,
                    "normalized_peak": peak.normalized_magnitude,
                    "peak_loss_db": 20.0
                    * np.log10(
                        max(peak.normalized_magnitude, np.finfo(float).tiny)
                    ),
                }
            )
    return rows


def _monte_carlo_rows(
    waveforms: list[FmWaveform],
    config: FmWaveformConfig,
    *,
    snr_values_db: list[float],
    trials: int,
    seed: int,
    mobile_doppler_hz: float,
) -> list[dict[str, Any]]:
    conditions = [(snr, 0.0) for snr in snr_values_db]
    conditions.append((max(snr_values_db), mobile_doppler_hz))
    rows: list[dict[str, Any]] = []
    for condition_index, (snr_db, doppler_hz) in enumerate(conditions):
        condition_seed = seed + 10_000 * condition_index
        for waveform in waveforms:
            # Resetting to the same condition seed gives every waveform the
            # same Gaussian draws, reducing comparison variance.
            result = monte_carlo_toa(
                waveform,
                config,
                energy_snr_db=snr_db,
                trials=trials,
                rng=np.random.default_rng(condition_seed),
                doppler_hz=doppler_hz,
            )
            crlb_samples = (
                delay_crlb_std_s(waveform, snr_db) * config.sample_rate_hz
            )
            rows.append(
                {
                    "waveform": waveform.name,
                    "energy_snr_db": result.snr_db,
                    "doppler_hz": result.doppler_hz,
                    "trials": result.trials,
                    "bias_samples": result.bias_samples,
                    "rmse_samples": result.rmse_samples,
                    "rmse_m": SPEED_OF_LIGHT_M_S
                    * result.rmse_samples
                    / config.sample_rate_hz,
                    "crlb_std_samples": crlb_samples,
                    "crlb_std_m": SPEED_OF_LIGHT_M_S
                    * crlb_samples
                    / config.sample_rate_hz,
                    "outlier_rate": result.outlier_rate,
                }
            )
    return rows


def _write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    if not rows:
        raise ValueError("cannot write an empty result table")
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def run_experiment(
    output: Path,
    *,
    trials: int,
    seed: int,
    snr_values_db: list[float],
) -> dict[str, Any]:
    # Capture provenance before creating output files, so a clean source tree
    # remains recorded as clean when the output directory is inside the repo.
    provenance = _git_provenance()
    config = FmWaveformConfig()
    carrier_hz = 868_000_000.0
    mobile_speed_m_s = 30.0
    mobile_doppler_hz = carrier_hz * mobile_speed_m_s / SPEED_OF_LIGHT_M_S
    crlb_snr_db = max(snr_values_db)

    lfm = make_lfm_waveform(config)
    nlfm = make_sinusoidal_nlfm_waveform(config)
    optimization = optimize_harmonic_fm(
        config, design_doppler_hz=mobile_doppler_hz
    )
    optimized = optimization.waveform
    waveforms = [lfm, nlfm, optimized]

    metrics = [
        _metric_row(
            waveform,
            config,
            crlb_snr_db=crlb_snr_db,
            mobile_doppler_hz=mobile_doppler_hz,
        )
        for waveform in waveforms
    ]
    ambiguity_grid = list(np.linspace(-500.0, 500.0, 41))
    ambiguity_grid.extend([-mobile_doppler_hz, mobile_doppler_hz])
    ambiguity_grid = sorted(set(float(value) for value in ambiguity_grid))
    ambiguity = _ambiguity_rows(waveforms, config, ambiguity_grid)
    monte_carlo = _monte_carlo_rows(
        waveforms,
        config,
        snr_values_db=snr_values_db,
        trials=trials,
        seed=seed,
        mobile_doppler_hz=mobile_doppler_hz,
    )

    output.mkdir(parents=True, exist_ok=True)
    _write_csv(output / "waveform-metrics.csv", metrics)
    _write_csv(output / "ambiguity-cuts.csv", ambiguity)
    _write_csv(output / "monte-carlo-toa.csv", monte_carlo)

    report: dict[str, Any] = {
        "schema_version": 1,
        "generated_utc": datetime.now(UTC).isoformat(),
        "generator": "tools/run_fm_positioning_experiment.py",
        "git": provenance,
        "configuration": {
            "sample_rate_hz": config.sample_rate_hz,
            "duration_s": config.duration_s,
            "sample_count": config.sample_count,
            "swept_bandwidth_hz": config.bandwidth_hz,
            "energy": config.energy,
            "carrier_hz": carrier_hz,
            "mobile_speed_m_s": mobile_speed_m_s,
            "mobile_doppler_hz": mobile_doppler_hz,
            "monte_carlo_trials_per_case": trials,
            "monte_carlo_seed": seed,
            "energy_snr_values_db": snr_values_db,
        },
        "optimization": {
            "family": "two-harmonic monotone endpoint-preserving FM",
            "objective": (
                "0.85 * delay-CRLB-std/LFM + "
                "0.15 * abs-Doppler-delay/LFM"
            ),
            "constraints": {
                "peak_sidelobe_db_max": -10.0,
                "integrated_sidelobe_db_max": -1.5,
                "minimum_normalized_slope": 0.02,
            },
            "design_doppler_hz": mobile_doppler_hz,
            "selected_harmonic_coefficients": list(
                optimized.harmonic_coefficients
            ),
            "relative_score": optimization.score,
            "feasible_candidates_evaluated": optimization.evaluated_candidates,
        },
        "metrics": metrics,
        "files": {
            "waveform_metrics": "waveform-metrics.csv",
            "ambiguity_cuts": "ambiguity-cuts.csv",
            "monte_carlo_toa": "monte-carlo-toa.csv",
        },
    }
    (output / "summary.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("artifacts/fm-positioning"),
        help="directory for JSON and CSV results",
    )
    parser.add_argument("--trials", type=int, default=2_000)
    parser.add_argument("--seed", type=int, default=20_260_921)
    parser.add_argument(
        "--snr-db",
        type=float,
        nargs="+",
        default=[0.0, 5.0, 10.0, 15.0, 20.0],
        help="Es/N0 values for the zero-Doppler Monte Carlo",
    )
    args = parser.parse_args()
    if args.trials < 1:
        parser.error("--trials must be positive")
    if not args.snr_db or not all(np.isfinite(args.snr_db)):
        parser.error("--snr-db must contain finite values")

    report = run_experiment(
        args.output,
        trials=args.trials,
        seed=args.seed,
        snr_values_db=sorted(set(args.snr_db)),
    )
    print(f"Results: {args.output.resolve()}")
    print(
        "Optimized coefficients: "
        f"{report['optimization']['selected_harmonic_coefficients']}"
    )
    for row in report["metrics"]:
        print(
            f"{row['waveform']:>16}: beta_rms={row['rms_bandwidth_hz'] / 1e3:7.3f} kHz, "
            f"PSL={row['peak_sidelobe_db']:7.3f} dB, "
            f"mobile bias={row['mobile_peak_bias_m']:8.3f} m"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
