"""FM waveform primitives and positioning-oriented quality metrics.

The functions in this module deliberately stay independent of the packet and
RTL models.  They use the same complex-baseband, NumPy-array conventions as the
CSS reference model, which makes the experiment useful without implying that a
new waveform is already compatible with the LoRa modem implementation.
"""

from __future__ import annotations

from dataclasses import dataclass
from itertools import product

import numpy as np
from numpy.typing import ArrayLike, NDArray

from .toa import estimate_toa


ComplexArray = NDArray[np.complex128]
FloatArray = NDArray[np.float64]
SPEED_OF_LIGHT_M_S = 299_792_458.0


@dataclass(frozen=True)
class FmWaveformConfig:
    """Shared duration, swept bandwidth, sample rate, and energy definition."""

    sample_rate_hz: float = 1_000_000.0
    duration_s: float = 1.024e-3
    bandwidth_hz: float = 125_000.0
    energy: float = 1.0

    def __post_init__(self) -> None:
        if not np.isfinite(self.sample_rate_hz) or self.sample_rate_hz <= 0.0:
            raise ValueError("sample_rate_hz must be finite and positive")
        if not np.isfinite(self.duration_s) or self.duration_s <= 0.0:
            raise ValueError("duration_s must be finite and positive")
        if not np.isfinite(self.bandwidth_hz) or self.bandwidth_hz <= 0.0:
            raise ValueError("bandwidth_hz must be finite and positive")
        if self.bandwidth_hz >= self.sample_rate_hz:
            raise ValueError("bandwidth_hz must be below the sample rate")
        if not np.isfinite(self.energy) or self.energy <= 0.0:
            raise ValueError("energy must be finite and positive")
        exact_count = self.sample_rate_hz * self.duration_s
        if not np.isclose(exact_count, round(exact_count), atol=1e-9, rtol=0.0):
            raise ValueError("sample_rate_hz * duration_s must be an integer")
        if round(exact_count) < 16:
            raise ValueError("the waveform must contain at least 16 samples")

    @property
    def sample_count(self) -> int:
        return int(round(self.sample_rate_hz * self.duration_s))


@dataclass(frozen=True)
class FmWaveform:
    """One finite FM waveform and the instantaneous-frequency law that made it."""

    name: str
    samples: ComplexArray
    instantaneous_frequency_hz: FloatArray
    harmonic_coefficients: tuple[float, ...]


@dataclass(frozen=True)
class AutocorrelationMetrics:
    """Aperiodic matched-filter metrics normalized to the zero-lag peak."""

    mainlobe_width_samples: int
    mainlobe_width_s: float
    peak_sidelobe_db: float
    integrated_sidelobe_db: float


@dataclass(frozen=True)
class AmbiguityPeak:
    """Peak of one delay cut through the delay-Doppler ambiguity function."""

    doppler_hz: float
    delay_samples: float
    normalized_magnitude: float


@dataclass(frozen=True)
class ToaMonteCarloResult:
    """Summary of repeated matched-filter ToA estimates."""

    snr_db: float
    doppler_hz: float
    trials: int
    bias_samples: float
    rmse_samples: float
    outlier_rate: float


@dataclass(frozen=True)
class OptimizationResult:
    """Selected harmonic law and its score relative to the LFM baseline."""

    waveform: FmWaveform
    score: float
    evaluated_candidates: int


def harmonic_frequency_law(
    config: FmWaveformConfig,
    coefficients: tuple[float, ...] = (),
    *,
    minimum_normalized_slope: float = 0.02,
) -> FloatArray:
    """Return a monotone endpoint-preserving FM law.

    With normalized time ``x`` in ``[-1, 1]`` the law is

    ``f(x) = B/2 * (x + sum(a_k sin(k*pi*x)))``.

    Empty coefficients give classic LFM.  Harmonic terms reshape how long the
    signal dwells in each part of the same ``[-B/2, B/2]`` sweep.  Requiring a
    positive derivative keeps the law monotone and avoids hidden frequency
    reversals in the optimized candidate set.
    """

    x = np.linspace(-1.0, 1.0, config.sample_count, dtype=np.float64)
    normalized = x.copy()
    derivative = np.ones_like(x)
    for index, coefficient in enumerate(coefficients, start=1):
        if not np.isfinite(coefficient):
            raise ValueError("harmonic coefficients must be finite")
        normalized += coefficient * np.sin(index * np.pi * x)
        derivative += coefficient * index * np.pi * np.cos(index * np.pi * x)
    if float(np.min(derivative)) < minimum_normalized_slope:
        raise ValueError("harmonic coefficients do not define a monotone sweep")
    return 0.5 * config.bandwidth_hz * normalized


def make_fm_waveform(
    name: str,
    config: FmWaveformConfig,
    coefficients: tuple[float, ...] = (),
) -> FmWaveform:
    """Generate a unit-convention complex FM waveform from a harmonic law."""

    frequency = harmonic_frequency_law(config, coefficients)
    phase_cycles = np.zeros(config.sample_count, dtype=np.float64)
    phase_cycles[1:] = np.cumsum(
        0.5 * (frequency[:-1] + frequency[1:]) / config.sample_rate_hz
    )
    samples = np.exp(2j * np.pi * phase_cycles)
    samples *= np.sqrt(config.energy / float(np.vdot(samples, samples).real))
    return FmWaveform(
        name=name,
        samples=samples.astype(np.complex128, copy=False),
        instantaneous_frequency_hz=frequency,
        harmonic_coefficients=tuple(float(value) for value in coefficients),
    )


def make_lfm_waveform(config: FmWaveformConfig) -> FmWaveform:
    """Generate the classic linear sweep baseline."""

    return make_fm_waveform("lfm", config)


def make_sinusoidal_nlfm_waveform(
    config: FmWaveformConfig, *, coefficient: float = 0.28
) -> FmWaveform:
    """Generate an edge-dwelling sinusoidal NLFM comparison waveform."""

    return make_fm_waveform("sinusoidal_nlfm", config, (coefficient, 0.0))


def rms_bandwidth_hz(waveform: FmWaveform) -> float:
    """Return the energy-weighted RMS bandwidth of the interior FM law.

    This is the central second moment of instantaneous frequency.  It excludes
    the common ideal rectangular pulse-gating edge, whose unlimited bandwidth
    would otherwise obscure the comparison between phase laws.
    """

    power = np.abs(waveform.samples) ** 2
    total = float(np.sum(power))
    mean = float(np.sum(power * waveform.instantaneous_frequency_hz) / total)
    variance = float(
        np.sum(power * (waveform.instantaneous_frequency_hz - mean) ** 2) / total
    )
    return float(np.sqrt(max(variance, 0.0)))


def delay_crlb_std_s(waveform: FmWaveform, energy_snr_db: float) -> float:
    """Known-waveform delay CRLB standard deviation for complex AWGN.

    ``energy_snr_db`` is ``Es/N0``.  Unknown constant carrier phase is treated
    as a nuisance parameter, hence the central (RMS) rather than raw second
    frequency moment.
    """

    if not np.isfinite(energy_snr_db):
        raise ValueError("energy_snr_db must be finite")
    beta = rms_bandwidth_hz(waveform)
    snr = 10.0 ** (energy_snr_db / 10.0)
    return float(1.0 / np.sqrt(8.0 * np.pi**2 * snr * beta**2))


def _fft_correlation(first: ComplexArray, second: ComplexArray) -> ComplexArray:
    """Return the full aperiodic correlation using a zero-padded FFT."""

    output_size = first.size + second.size - 1
    fft_size = 1 << (output_size - 1).bit_length()
    spectrum = np.fft.fft(first, fft_size) * np.fft.fft(
        np.conjugate(second[::-1]), fft_size
    )
    return np.fft.ifft(spectrum)[:output_size]


def _first_local_minimum(values: FloatArray, start: int, direction: int) -> int:
    index = start + direction
    while 0 < index < values.size - 1:
        if values[index] <= values[index - 1] and values[index] <= values[index + 1]:
            return index
        index += direction
    raise ValueError("autocorrelation has no resolvable mainlobe boundary")


def autocorrelation_metrics(
    waveform: FmWaveform, sample_rate_hz: float
) -> AutocorrelationMetrics:
    """Measure null-to-null mainlobe width, PSL, and ISL."""

    correlation = _fft_correlation(waveform.samples, waveform.samples)
    magnitude = np.abs(correlation)
    center = waveform.samples.size - 1
    magnitude /= magnitude[center]
    left = _first_local_minimum(magnitude, center, -1)
    right = _first_local_minimum(magnitude, center, 1)
    mainlobe = np.zeros(magnitude.size, dtype=bool)
    mainlobe[left : right + 1] = True
    sidelobe_peak = float(np.max(magnitude[~mainlobe]))
    sidelobe_energy = float(np.sum(magnitude[~mainlobe] ** 2))
    mainlobe_energy = float(np.sum(magnitude[mainlobe] ** 2))
    return AutocorrelationMetrics(
        mainlobe_width_samples=right - left,
        mainlobe_width_s=(right - left) / sample_rate_hz,
        peak_sidelobe_db=float(
            20.0 * np.log10(max(sidelobe_peak, np.finfo(float).tiny))
        ),
        integrated_sidelobe_db=float(
            10.0
            * np.log10(
                max(sidelobe_energy / mainlobe_energy, np.finfo(float).tiny)
            )
        ),
    )


def ambiguity_peak(
    waveform: FmWaveform, sample_rate_hz: float, doppler_hz: float
) -> AmbiguityPeak:
    """Find the fractional-delay peak of an aperiodic ambiguity cut."""

    sample_indices = np.arange(waveform.samples.size, dtype=np.float64)
    shifted = waveform.samples * np.exp(
        2j * np.pi * doppler_hz * sample_indices / sample_rate_hz
    )
    correlation = _fft_correlation(shifted, waveform.samples)
    metric = np.abs(correlation) ** 2
    peak = int(np.argmax(metric))
    fractional = 0.0
    if 0 < peak < metric.size - 1:
        left, center, right = metric[peak - 1 : peak + 2]
        denominator = left - 2.0 * center + right
        if denominator != 0.0:
            fractional = float(np.clip(0.5 * (left - right) / denominator, -0.5, 0.5))
    delay = peak + fractional - (waveform.samples.size - 1)
    peak_magnitude = float(np.sqrt(metric[peak]))
    energy = float(np.vdot(waveform.samples, waveform.samples).real)
    return AmbiguityPeak(
        doppler_hz=float(doppler_hz),
        delay_samples=float(delay),
        normalized_magnitude=peak_magnitude / energy,
    )


def _relative_optimization_score(
    waveform: FmWaveform,
    baseline: FmWaveform,
    config: FmWaveformConfig,
    design_doppler_hz: float,
) -> float:
    candidate_doppler = np.mean(
        [
            abs(ambiguity_peak(waveform, config.sample_rate_hz, sign * design_doppler_hz).delay_samples)
            for sign in (-1.0, 1.0)
        ]
    )
    baseline_doppler = np.mean(
        [
            abs(ambiguity_peak(baseline, config.sample_rate_hz, sign * design_doppler_hz).delay_samples)
            for sign in (-1.0, 1.0)
        ]
    )
    crlb_ratio = rms_bandwidth_hz(baseline) / rms_bandwidth_hz(waveform)
    doppler_ratio = candidate_doppler / max(baseline_doppler, np.finfo(float).eps)
    return float(0.85 * crlb_ratio + 0.15 * doppler_ratio)


def optimize_harmonic_fm(
    config: FmWaveformConfig,
    *,
    first_harmonics: ArrayLike | None = None,
    second_harmonics: ArrayLike | None = None,
    design_doppler_hz: float = 100.0,
    maximum_peak_sidelobe_db: float = -10.0,
    maximum_integrated_sidelobe_db: float = -1.5,
) -> OptimizationResult:
    """Grid-search a deterministic two-harmonic law for positioning metrics.

    The scalar objective uses relative quantities so it remains dimensionless:
    85% delay-CRLB standard deviation and 15% absolute ambiguity-peak
    displacement at ``±design_doppler_hz``.  Candidates must also satisfy the
    supplied PSL and ISL ceilings.  LFM therefore has score 1.0.  This is an
    exploratory constrained search, not a claim of global optimality over all
    possible FM laws.
    """

    if not np.isfinite(design_doppler_hz) or design_doppler_hz <= 0.0:
        raise ValueError("design_doppler_hz must be finite and positive")
    first = (
        np.linspace(-0.04, 0.30, 18)
        if first_harmonics is None
        else np.asarray(first_harmonics, dtype=np.float64)
    )
    second = (
        np.linspace(-0.06, 0.06, 13)
        if second_harmonics is None
        else np.asarray(second_harmonics, dtype=np.float64)
    )
    baseline = make_lfm_waveform(config)
    best_waveform = baseline
    best_score = 1.0
    evaluated = 0
    for first_value, second_value in product(first, second):
        coefficients = (float(first_value), float(second_value))
        try:
            candidate = make_fm_waveform("optimized_fm", config, coefficients)
        except ValueError:
            continue
        candidate_ac = autocorrelation_metrics(candidate, config.sample_rate_hz)
        if candidate_ac.peak_sidelobe_db > maximum_peak_sidelobe_db:
            continue
        if candidate_ac.integrated_sidelobe_db > maximum_integrated_sidelobe_db:
            continue
        score = _relative_optimization_score(
            candidate, baseline, config, design_doppler_hz
        )
        evaluated += 1
        if score < best_score:
            best_waveform = candidate
            best_score = score
    return OptimizationResult(
        waveform=best_waveform,
        score=float(best_score),
        evaluated_candidates=evaluated,
    )


def monte_carlo_toa(
    waveform: FmWaveform,
    config: FmWaveformConfig,
    *,
    energy_snr_db: float,
    trials: int,
    rng: np.random.Generator,
    doppler_hz: float = 0.0,
    true_delay_samples: int = 32,
    guard_samples: int = 32,
) -> ToaMonteCarloResult:
    """Run grid-aligned ToA estimation in complex AWGN and optional Doppler."""

    if trials < 1:
        raise ValueError("trials must be positive")
    if true_delay_samples < 0 or guard_samples < 1:
        raise ValueError("delays and guards must be non-negative with a positive guard")
    if true_delay_samples > 2 * guard_samples:
        raise ValueError("true_delay_samples must lie inside the search guard")
    received_size = waveform.samples.size + 2 * guard_samples
    clean = np.zeros(received_size, dtype=np.complex128)
    clean[
        true_delay_samples : true_delay_samples + waveform.samples.size
    ] = waveform.samples
    indices = np.arange(received_size, dtype=np.float64)
    clean *= np.exp(2j * np.pi * doppler_hz * indices / config.sample_rate_hz)
    noise_power = config.energy / (10.0 ** (energy_snr_db / 10.0))
    noise_scale = np.sqrt(noise_power / 2.0)
    errors = np.empty(trials, dtype=np.float64)
    for trial in range(trials):
        noise = noise_scale * (
            rng.standard_normal(received_size) + 1j * rng.standard_normal(received_size)
        )
        estimate = estimate_toa(clean + noise, waveform.samples)
        errors[trial] = estimate.sample_index - true_delay_samples
    return ToaMonteCarloResult(
        snr_db=float(energy_snr_db),
        doppler_hz=float(doppler_hz),
        trials=int(trials),
        bias_samples=float(np.mean(errors)),
        rmse_samples=float(np.sqrt(np.mean(errors**2))),
        outlier_rate=float(np.mean(np.abs(errors) > 1.0)),
    )
