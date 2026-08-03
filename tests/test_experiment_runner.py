import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "run_phy_experiment", ROOT / "tools" / "run_phy_experiment.py"
)
assert SPEC is not None and SPEC.loader is not None
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)

SWEEP_SPEC = importlib.util.spec_from_file_location(
    "run_phy_sweep", ROOT / "tools" / "run_phy_sweep.py"
)
assert SWEEP_SPEC is not None and SWEEP_SPEC.loader is not None
SWEEP = importlib.util.module_from_spec(SWEEP_SPEC)
SWEEP_SPEC.loader.exec_module(SWEEP)


def load_example(name: str) -> dict:
    path = ROOT / "experiments" / "configs" / name
    return json.loads(path.read_text(encoding="utf-8"))


def test_pluto_plan_contains_arm_handshake_and_known_profile(tmp_path):
    config = load_example("one-machine-pluto.example.json")
    RUNNER.validate_config(config)

    commands = RUNNER.transmitter_commands(config)
    receiver = RUNNER.receiver_command(
        config, tmp_path / "capture", tmp_path / ".ready"
    )

    assert commands[0] == "stop"
    assert "set freq 868.100000" in commands
    assert "set sf 7" in commands
    assert "payload counter" in commands
    assert "--ready-file" in receiver
    assert receiver[receiver.index("--samples") + 1] == "4194304"
    assert receiver[receiver.index("--count") + 1] == "1"
    assert receiver[receiver.index("--timeout-ms") + 1] == "30000"


def test_rtl_plan_has_finite_capture(tmp_path):
    config = load_example("one-machine-rtl-sdr.example.json")
    RUNNER.validate_config(config)

    receiver = RUNNER.receiver_command(
        config, tmp_path / "capture", tmp_path / ".ready"
    )

    assert receiver[0] == "rtl_sdr"
    assert receiver[receiver.index("-n") + 1] == "4096000"
    assert receiver[-1].endswith("rtl-capture.cu8")


def test_capture_must_cover_the_transmit_sequence():
    config = load_example("one-machine-pluto.example.json")
    config["receiver"]["duration_s"] = 1.0

    with pytest.raises(ValueError, match="too short"):
        RUNNER.validate_config(config)


def test_run_name_cannot_escape_output_root():
    config = load_example("one-machine-pluto.example.json")
    config["run_name"] = "../outside"

    with pytest.raises(ValueError, match="run_name"):
        RUNNER.validate_config(config)


def test_rf_execution_requires_bench_description():
    config = load_example("one-machine-pluto.example.json")

    with pytest.raises(ValueError, match="antenna_or_cable_path"):
        RUNNER.validate_execution_config(config)

    config["bench"]["antenna_or_cable_path"] = "two antennas, 3 m OTA"
    RUNNER.validate_execution_config(config)


def test_airtime_increases_with_spreading_factor():
    config = load_example("one-machine-pluto.example.json")
    sf7 = RUNNER.lora_airtime_seconds(config["transmitter"])
    config["transmitter"]["spreading_factor"] = 12
    sf12 = RUNNER.lora_airtime_seconds(config["transmitter"])

    assert sf7 == pytest.approx(0.076032, rel=1e-6)
    assert sf12 > 1.5


def test_matlab_expression_uses_capture_metadata(tmp_path):
    config = load_example("one-machine-pluto.example.json")
    expression = RUNNER.matlab_expression(
        config, tmp_path / "capture.cf32", tmp_path / "analysis"
    )

    assert "analyze_iq_capture" in expression
    assert "'cf32'" in expression
    assert "1000000,868350000,868100000" in expression


def test_lr1121_sweep_cases_are_unique_and_valid():
    sweep = load_example("../sweeps/lr1121-pluto-modes.json")
    base = load_example("one-machine-pluto.example.json")
    base["bench"]["antenna_or_cable_path"] = "test bench"
    cases = SWEEP.prepare_cases(sweep, base, execute=True)

    assert len(cases) == 27
    assert len({name for name, _ in cases}) == len(cases)
    assert all(config["transmitter"]["power_dbm"] <= 0 for _, config in cases)
    assert all(config["transmitter"]["power_dbm"] >= -9 for _, config in cases)
    assert all(config["transmitter"]["frequency_hz"] == 868100000 for _, config in cases)


def test_heltec_v43_sweep_cases_are_unique_and_safe():
    sweep = load_example("../sweeps/heltec-v43-pluto-modes.json")
    base = load_example("one-machine-pluto.example.json")
    base["bench"]["antenna_or_cable_path"] = "test bench"
    base["transmitter"]["board"] = "Heltec WiFi LoRa 32 V4.3"
    base["transmitter"]["power_dbm"] = -9
    cases = SWEEP.prepare_cases(sweep, base, execute=True)

    assert len(cases) == 27
    assert len({name for name, _ in cases}) == len(cases)
    assert all(-9 <= config["transmitter"]["power_dbm"] <= -5 for _, config in cases)
    assert all(config["transmitter"]["frequency_hz"] == 868100000 for _, config in cases)
    assert {config["transmitter"]["spreading_factor"] for _, config in cases} >= set(
        range(5, 13)
    )
    assert {config["transmitter"]["bandwidth_hz"] for _, config in cases} >= {
        62500,
        125000,
        250000,
        500000,
    }
