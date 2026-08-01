import numpy as np
import pytest

from zynq_lora_phy import predict_tdoa, solve_tdoa, tdoa_from_toas


def test_tdoa_conversion_uses_receiver_zero_as_reference() -> None:
    result = tdoa_from_toas([1.0, 1.25, 0.75])

    np.testing.assert_allclose(result, [0.25, -0.25])


def test_noiseless_2d_position_is_recovered() -> None:
    receivers = np.array(
        [
            [0.0, 0.0],
            [100.0, 0.0],
            [100.0, 80.0],
            [0.0, 80.0],
        ]
    )
    true_position = np.array([31.0, 27.0])
    observations = predict_tdoa(true_position, receivers)

    result = solve_tdoa(receivers, observations)

    assert result.converged
    np.testing.assert_allclose(result.position_m, true_position, atol=1e-6)
    np.testing.assert_allclose(result.residual_s, 0.0, atol=1e-14)


def test_tdoa_solver_validates_observation_count() -> None:
    receivers = np.array([[0.0, 0.0], [1.0, 0.0], [0.0, 1.0]])

    with pytest.raises(ValueError):
        solve_tdoa(receivers, [0.0])
