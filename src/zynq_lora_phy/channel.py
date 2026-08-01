"""Deterministic channel-impairment helpers for reference-model tests."""

from __future__ import annotations

import numpy as np
from numpy.typing import ArrayLike, NDArray


ComplexArray = NDArray[np.complex128]


def apply_frequency_offset(
    samples: ArrayLike,
    frequency_offset_cycles_per_sample: float,
    *,
    initial_phase_rad: float = 0.0,
) -> ComplexArray:
    """Apply a normalized carrier-frequency and initial-phase offset."""

    array = np.asarray(samples, dtype=np.complex128)
    if array.ndim != 1:
        raise ValueError("samples must be a one-dimensional array")
    n = np.arange(array.size, dtype=np.float64)
    rotation = np.exp(
        1j * (2.0 * np.pi * frequency_offset_cycles_per_sample * n + initial_phase_rad)
    )
    return array * rotation


def add_awgn(
    samples: ArrayLike,
    snr_db: float,
    *,
    rng: np.random.Generator | None = None,
) -> ComplexArray:
    """Add circular complex white Gaussian noise at a measured signal SNR."""

    array = np.asarray(samples, dtype=np.complex128)
    if array.ndim != 1:
        raise ValueError("samples must be a one-dimensional array")
    if array.size == 0:
        return array.copy()
    signal_power = float(np.mean(np.abs(array) ** 2))
    if signal_power == 0.0:
        raise ValueError("cannot define SNR for an all-zero signal")
    generator = rng if rng is not None else np.random.default_rng()
    noise_power = signal_power / (10.0 ** (snr_db / 10.0))
    scale = np.sqrt(noise_power / 2.0)
    noise = scale * (
        generator.standard_normal(array.size) + 1j * generator.standard_normal(array.size)
    )
    return array + noise


def delay_signal(samples: ArrayLike, delay_samples: int) -> ComplexArray:
    """Prepend an integer number of zero samples without truncating the input."""

    if not isinstance(delay_samples, (int, np.integer)):
        raise TypeError("delay_samples must be an integer")
    if delay_samples < 0:
        raise ValueError("delay_samples must be non-negative")
    array = np.asarray(samples, dtype=np.complex128)
    if array.ndim != 1:
        raise ValueError("samples must be a one-dimensional array")
    return np.pad(array, (int(delay_samples), 0))
