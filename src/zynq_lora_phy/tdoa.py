"""TDoA observation and multilateration helpers."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import ArrayLike, NDArray


SPEED_OF_LIGHT_M_S = 299_792_458.0


@dataclass(frozen=True)
class PositionEstimate:
    """Result of an iterative TDoA least-squares solution."""

    position_m: NDArray[np.float64]
    residual_s: NDArray[np.float64]
    iterations: int
    converged: bool


def _geometry(
    position_m: ArrayLike, receiver_positions_m: ArrayLike
) -> tuple[NDArray[np.float64], NDArray[np.float64]]:
    position = np.asarray(position_m, dtype=np.float64)
    receivers = np.asarray(receiver_positions_m, dtype=np.float64)
    if position.ndim != 1:
        raise ValueError("position_m must be one-dimensional")
    if receivers.ndim != 2 or receivers.shape[1] != position.size:
        raise ValueError("receiver positions and position dimensions must match")
    if receivers.shape[0] < position.size + 1:
        raise ValueError("TDoA requires at least dimension + 1 receivers")
    return position, receivers


def tdoa_from_toas(toas_s: ArrayLike) -> NDArray[np.float64]:
    """Convert absolute ToAs to differences relative to receiver zero."""

    toas = np.asarray(toas_s, dtype=np.float64)
    if toas.ndim != 1 or toas.size < 2:
        raise ValueError("toas_s must contain at least two values")
    return toas[1:] - toas[0]


def predict_tdoa(
    position_m: ArrayLike,
    receiver_positions_m: ArrayLike,
    *,
    propagation_speed_m_s: float = SPEED_OF_LIGHT_M_S,
) -> NDArray[np.float64]:
    """Predict TDoA values relative to receiver zero for a candidate position."""

    if propagation_speed_m_s <= 0.0:
        raise ValueError("propagation_speed_m_s must be positive")
    position, receivers = _geometry(position_m, receiver_positions_m)
    ranges = np.linalg.norm(position - receivers, axis=1)
    return (ranges[1:] - ranges[0]) / propagation_speed_m_s


def solve_tdoa(
    receiver_positions_m: ArrayLike,
    tdoa_s: ArrayLike,
    *,
    initial_position_m: ArrayLike | None = None,
    propagation_speed_m_s: float = SPEED_OF_LIGHT_M_S,
    max_iterations: int = 50,
    tolerance_m: float = 1e-6,
) -> PositionEstimate:
    """Solve a calibrated TDoA system with Gauss-Newton least squares.

    Receiver zero is the reference. Good geometry and a reasonable initial
    position are required because hyperbolic localization can have ambiguous or
    poorly conditioned solutions.
    """

    receivers = np.asarray(receiver_positions_m, dtype=np.float64)
    observed = np.asarray(tdoa_s, dtype=np.float64)
    if receivers.ndim != 2:
        raise ValueError("receiver_positions_m must be a two-dimensional array")
    dimension = receivers.shape[1]
    if receivers.shape[0] < dimension + 1:
        raise ValueError("TDoA requires at least dimension + 1 receivers")
    if observed.shape != (receivers.shape[0] - 1,):
        raise ValueError("tdoa_s must contain one value per non-reference receiver")
    if propagation_speed_m_s <= 0.0:
        raise ValueError("propagation_speed_m_s must be positive")
    if max_iterations < 1:
        raise ValueError("max_iterations must be at least 1")
    if tolerance_m <= 0.0:
        raise ValueError("tolerance_m must be positive")

    if initial_position_m is None:
        position = np.mean(receivers, axis=0)
    else:
        position = np.asarray(initial_position_m, dtype=np.float64).copy()
        if position.shape != (dimension,):
            raise ValueError("initial_position_m dimension does not match receivers")

    converged = False
    iterations = 0
    for iterations in range(1, max_iterations + 1):
        offsets = position - receivers
        ranges = np.linalg.norm(offsets, axis=1)
        safe_ranges = np.maximum(ranges, np.finfo(np.float64).eps)
        predicted = (ranges[1:] - ranges[0]) / propagation_speed_m_s
        residual = predicted - observed
        unit_vectors = offsets / safe_ranges[:, None]
        jacobian = (unit_vectors[1:] - unit_vectors[0]) / propagation_speed_m_s
        step, *_ = np.linalg.lstsq(jacobian, -residual, rcond=None)
        position += step
        if np.linalg.norm(step) <= tolerance_m:
            converged = True
            break

    final_residual = (
        predict_tdoa(
            position,
            receivers,
            propagation_speed_m_s=propagation_speed_m_s,
        )
        - observed
    )
    return PositionEstimate(
        position_m=position,
        residual_s=final_residual,
        iterations=iterations,
        converged=converged,
    )
