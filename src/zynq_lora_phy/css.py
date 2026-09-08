"""Floating-point cyclic chirp spread spectrum primitives.

This is a deliberately small symbol-level model. It establishes signal and bin
conventions for later synchronization, packet coding, fixed-point, and RTL work;
it is not yet a complete LoRa packet implementation.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import numpy as np
from numpy.typing import ArrayLike, NDArray


ComplexArray = NDArray[np.complex128]


@dataclass(frozen=True)
class CssConfig:
    """CSS symbol parameters.

    `samples_per_chip` is an integer oversampling factor. The normalized model
    uses one complex sample per chip by default; a physical sample rate can be
    attached later through `sample_rate_hz` in experiment metadata.
    """

    spreading_factor: int = 7
    samples_per_chip: int = 1

    def __post_init__(self) -> None:
        if not 5 <= self.spreading_factor <= 12:
            raise ValueError("spreading_factor must be between 5 and 12")
        if self.samples_per_chip < 1:
            raise ValueError("samples_per_chip must be at least 1")
        if not isinstance(self.samples_per_chip, int):
            raise TypeError("samples_per_chip must be an integer")

    @property
    def symbol_count(self) -> int:
        """Number of distinct CSS symbols, equal to 2**SF."""

        return 1 << self.spreading_factor

    @property
    def samples_per_symbol(self) -> int:
        """Number of complex samples in one symbol."""

        return self.symbol_count * self.samples_per_chip


def reference_chirp(config: CssConfig, *, up: bool = True) -> ComplexArray:
    """Generate one unit-amplitude periodic reference chirp.

    The discrete-time convention is chosen so that a negative cyclic shift by
    `symbol * samples_per_chip`, followed by dechirping, produces a positive FFT
    tone at that shift. This convention is deterministic and convenient for
    golden-vector generation.
    """

    sample_count = config.samples_per_symbol
    n = np.arange(sample_count, dtype=np.float64)
    oversampling = config.samples_per_chip
    phase_cycles = (
        0.5 * n * n / (config.symbol_count * oversampling * oversampling)
        - 0.5 * n / oversampling
    )
    chirp = np.exp(2j * np.pi * phase_cycles)
    if not up:
        chirp = np.conjugate(chirp)
    return chirp.astype(np.complex128, copy=False)


def modulate_symbol(symbol: int, config: CssConfig) -> ComplexArray:
    """Modulate one integer symbol as a cyclic shift of the upchirp."""

    if not isinstance(symbol, (int, np.integer)):
        raise TypeError("symbol must be an integer")
    if not 0 <= int(symbol) < config.symbol_count:
        raise ValueError(f"symbol must be in [0, {config.symbol_count})")
    shift = int(symbol) * config.samples_per_chip
    return np.roll(reference_chirp(config), -shift)


def modulate(symbols: Iterable[int], config: CssConfig) -> ComplexArray:
    """Modulate an iterable of symbols into a contiguous complex waveform."""

    symbol_list = list(symbols)
    if not symbol_list:
        return np.empty(0, dtype=np.complex128)
    return np.concatenate([modulate_symbol(symbol, config) for symbol in symbol_list])


def _validate_symbol_samples(samples: ArrayLike, config: CssConfig) -> ComplexArray:
    array = np.asarray(samples, dtype=np.complex128)
    if array.ndim != 1:
        raise ValueError("samples must be a one-dimensional array")
    if array.size != config.samples_per_symbol:
        raise ValueError(
            f"expected {config.samples_per_symbol} samples, got {array.size}"
        )
    return array


def demodulate_symbol(
    samples: ArrayLike,
    config: CssConfig,
    *,
    frequency_offset_cycles_per_sample: float = 0.0,
) -> int:
    """Dechirp one aligned symbol and return its maximum-likelihood bin.

    The optional normalized frequency offset is removed before dechirping. For a
    physical sample rate `fs`, pass `cfo_hz / fs`.
    """

    array = _validate_symbol_samples(samples, config)
    n = np.arange(array.size, dtype=np.float64)
    compensation = np.exp(-2j * np.pi * frequency_offset_cycles_per_sample * n)
    dechirped = array * compensation * np.conjugate(reference_chirp(config))
    chip_rate_samples = dechirped[:: config.samples_per_chip]
    peak_bin = int(np.argmax(np.abs(np.fft.fft(chip_rate_samples)) ** 2))
    return peak_bin % config.symbol_count


def demodulate(
    samples: ArrayLike,
    config: CssConfig,
    *,
    frequency_offset_cycles_per_sample: float = 0.0,
) -> NDArray[np.int64]:
    """Demodulate an aligned waveform containing an integer number of symbols."""

    array = np.asarray(samples, dtype=np.complex128)
    if array.ndim != 1:
        raise ValueError("samples must be a one-dimensional array")
    symbol_size = config.samples_per_symbol
    if array.size % symbol_size:
        raise ValueError("sample count must be an integer number of symbols")
    result = [
        demodulate_symbol(
            array[start : start + symbol_size],
            config,
            frequency_offset_cycles_per_sample=frequency_offset_cycles_per_sample,
        )
        for start in range(0, array.size, symbol_size)
    ]
    return np.asarray(result, dtype=np.int64)


def estimate_frequency_offset(
    samples: ArrayLike,
    config: CssConfig,
    *,
    known_symbol: int = 0,
) -> float:
    """Estimate normalized CFO from one aligned, known CSS symbol.

    The estimator fits a line to the unwrapped phase after dechirping. It is
    unambiguous over ±0.5 cycles/sample and is primarily intended for preamble
    upchirps in the initial reference model.
    """

    array = _validate_symbol_samples(samples, config)
    known = modulate_symbol(known_symbol, config)
    dechirped = array * np.conjugate(known)
    phase = np.unwrap(np.angle(dechirped))
    n = np.arange(phase.size, dtype=np.float64)
    centered_n = n - np.mean(n)
    slope_rad_per_sample = np.dot(centered_n, phase) / np.dot(centered_n, centered_n)
    return float(slope_rad_per_sample / (2.0 * np.pi))


@dataclass(frozen=True)
class CorrelatorStages:
    """Every intermediate of the HDL-oriented CSS FFT correlator.

    This mirrors the authoritative MATLAB ``lora_phy.fft_correlator_stages``,
    including its ``1/M`` normalization, so a stage-by-stage differential can
    compare a Python, Simulink, or RTL implementation against the same
    numerical definition rather than against a re-derived one.

    Arrays are indexed ``[window, ...]``: ``windows`` and ``product`` are
    ``M``-wide, ``partition`` through ``magnitude_squared`` are ``N``-wide.
    """

    windows: ComplexArray
    reference: ComplexArray
    reference_spectrum: ComplexArray
    fft_m: ComplexArray
    product: ComplexArray
    partition: ComplexArray
    fft_n: ComplexArray
    magnitude_squared: NDArray[np.float64]
    peak_power: NDArray[np.float64]
    second_power: NDArray[np.float64]
    symbols: NDArray[np.int64]
    second_symbols: NDArray[np.int64]
    confidence: NDArray[np.float64]


def fft_correlator_stages(
    windows: ArrayLike,
    config: CssConfig,
    *,
    reference: ArrayLike | None = None,
) -> CorrelatorStages:
    """Run the two-FFT correlator identity and expose every intermediate.

    ``windows`` is either one symbol window or a ``(count, M)`` stack of them.
    For ``M = N*L`` the ``M``-point inverse transform needed for lags ``-k*L``
    reduces to an ``N``-point forward transform after aliasing the frequency
    bins ``q = m + r*N``, which is what the generated DUT computes.
    """

    stack = np.atleast_2d(np.asarray(windows, dtype=np.complex128))
    if stack.ndim != 2:
        raise ValueError("windows must be one or two dimensional")
    size = config.samples_per_symbol
    if stack.shape[1] != size:
        raise ValueError(f"each window must hold {size} samples")

    if reference is None:
        reference_array = reference_chirp(config)
    else:
        reference_array = np.asarray(reference, dtype=np.complex128)
        if reference_array.shape != (size,):
            raise ValueError(f"reference must hold exactly {size} samples")
        if not np.any(reference_array):
            raise ValueError("reference must contain non-zero energy")

    reference_spectrum = np.fft.fft(reference_array)
    fft_m = np.fft.fft(stack, axis=1)
    product = fft_m * np.conjugate(reference_spectrum)
    # MATLAB reshapes each M-vector as N x L in column-major order.  Express
    # the same q=r+m*N partition explicitly rather than relying on a
    # language-specific reshape convention.
    partition = product.reshape(
        stack.shape[0], config.samples_per_chip, config.symbol_count
    ).sum(axis=1)
    fft_n = np.fft.fft(partition, axis=1) / size
    magnitude_squared = np.abs(fft_n) ** 2

    order = np.argsort(magnitude_squared, axis=1)
    symbols = order[:, -1].astype(np.int64)
    second_symbols = order[:, -2].astype(np.int64)
    rows = np.arange(stack.shape[0])
    peak_power = magnitude_squared[rows, symbols]
    second_power = magnitude_squared[rows, second_symbols]
    total = np.maximum(magnitude_squared.sum(axis=1), np.finfo(np.float64).eps)

    return CorrelatorStages(
        windows=stack,
        reference=reference_array,
        reference_spectrum=reference_spectrum,
        fft_m=fft_m,
        product=product,
        partition=partition,
        fft_n=fft_n,
        magnitude_squared=magnitude_squared,
        peak_power=peak_power,
        second_power=second_power,
        symbols=symbols,
        second_symbols=second_symbols,
        confidence=peak_power / total,
    )
