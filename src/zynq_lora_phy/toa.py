"""Matched-filter time-of-arrival estimation."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import ArrayLike


@dataclass(frozen=True)
class ToaEstimate:
    """Arrival estimate relative to the first received sample."""

    sample_index: float
    peak_magnitude: float


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
