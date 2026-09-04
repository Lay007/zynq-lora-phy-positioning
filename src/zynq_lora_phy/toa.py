"""Matched-filter time-of-arrival estimation."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import ArrayLike

from .css import CssConfig, reference_chirp


@dataclass(frozen=True)
class ToaEstimate:
    """Arrival estimate relative to the first received sample."""

    sample_index: float
    peak_magnitude: float


@dataclass(frozen=True)
class JointChirpTimingEstimate:
    """Timing and CFO-induced displacement from one up/down chirp pair.

    Carrier offset moves the matched-filter peaks of an upchirp and downchirp
    in opposite directions. Their half-sum retains the common timing offset;
    their half-difference is the CFO-equivalent displacement in samples.
    """

    up_sample_index: float
    down_sample_index: float
    up_offset_samples: float
    down_offset_samples: float
    timing_offset_samples: float
    cfo_displacement_samples: float
    correction_samples: int


def estimate_toa(received: ArrayLike, reference: ArrayLike) -> ToaEstimate:
    """Estimate ToA by complex matched filtering and parabolic interpolation.

    The returned sample index is the start of the reference in `received`. The
    fractional interpolation is a local peak refinement, not yet a calibrated
    wideband delay estimator.
    """

    rx = np.asarray(received, dtype=np.complex128)
    ref = np.asarray(reference, dtype=np.complex128)
    if rx.ndim != 1 or ref.ndim != 1:
        raise ValueError("received and reference must be one-dimensional")
    if ref.size == 0:
        raise ValueError("reference must not be empty")
    if rx.size < ref.size:
        raise ValueError("received must be at least as long as reference")
    if not np.any(ref):
        raise ValueError("reference must contain non-zero energy")

    correlation = np.correlate(rx, ref, mode="valid")
    metric = np.abs(correlation) ** 2
    peak_index = int(np.argmax(metric))
    fractional = 0.0
    if 0 < peak_index < metric.size - 1:
        left, center, right = metric[peak_index - 1 : peak_index + 2]
        denominator = left - 2.0 * center + right
        if denominator != 0.0:
            fractional = float(0.5 * (left - right) / denominator)
            fractional = float(np.clip(fractional, -0.5, 0.5))

    return ToaEstimate(
        sample_index=peak_index + fractional,
        peak_magnitude=float(np.sqrt(metric[peak_index])),
    )


def estimate_joint_chirp_timing(
    received: ArrayLike,
    up_start: int,
    down_start: int,
    config: CssConfig,
    *,
    search_radius: int,
) -> JointChirpTimingEstimate:
    """Estimate a sample-resolution grid correction from up/down chirps.

    ``up_start`` and ``down_start`` are coarse absolute sample indices for one
    preamble upchirp and one full SFD downchirp. Each matched filter searches
    ``search_radius`` samples either side of its coarse index. Averaging their
    offsets cancels the equal-and-opposite peak displacement caused by CFO.

    ``correction_samples`` uses ties-away-from-zero rounding, matching MATLAB
    and the integer policy intended for RTL. Positive values advance the next
    symbol-grid boundary in the input stream.
    """

    array = np.asarray(received, dtype=np.complex128)
    if array.ndim != 1:
        raise ValueError("received must be one-dimensional")
    if not isinstance(up_start, (int, np.integer)) or not isinstance(
        down_start, (int, np.integer)
    ):
        raise TypeError("chirp starts must be integers")
    if not isinstance(search_radius, (int, np.integer)):
        raise TypeError("search_radius must be an integer")
    if search_radius < 1:
        raise ValueError("search_radius must be positive")

    reference_up = reference_chirp(config)
    reference_down = np.conjugate(reference_up)
    reference_size = config.samples_per_symbol

    def search(coarse_start: int, reference: np.ndarray) -> float:
        first = int(coarse_start) - int(search_radius)
        last = int(coarse_start) + reference_size + int(search_radius)
        if first < 0 or last > array.size:
            raise ValueError("a chirp search window falls outside received")
        local = estimate_toa(array[first:last], reference)
        return first + local.sample_index

    up_index = search(int(up_start), reference_up)
    down_index = search(int(down_start), reference_down)
    up_offset = up_index - int(up_start)
    down_offset = down_index - int(down_start)
    timing = 0.5 * (up_offset + down_offset)
    cfo_displacement = 0.5 * (up_offset - down_offset)
    correction = int(np.sign(timing) * np.floor(abs(timing) + 0.5))

    return JointChirpTimingEstimate(
        up_sample_index=up_index,
        down_sample_index=down_index,
        up_offset_samples=up_offset,
        down_offset_samples=down_offset,
        timing_offset_samples=timing,
        cfo_displacement_samples=cfo_displacement,
        correction_samples=correction,
    )
