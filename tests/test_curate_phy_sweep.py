import hashlib
import importlib.util
import json
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "curate_phy_sweep", ROOT / "tools" / "curate_phy_sweep.py"
)
assert SPEC is not None and SPEC.loader is not None
CURATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CURATOR)


def make_sweep(root: Path, name: str = "sf7-bw125") -> Path:
    sweep = root / "sweep"
    run = sweep / "runs" / name
    capture_directory = run / "capture"
    capture_directory.mkdir(parents=True)
    samples = b"\x00\x00\x80?\x00\x00\x00\x00" * 8
    capture = capture_directory / "input.cf32"
    capture.write_bytes(samples)
    digest = hashlib.sha256(samples).hexdigest()
    result = {
        "status": "complete",
        "run_id": f"run-{name}",
        "repository_commit": "a" * 40,
        "repository_dirty": False,
        "config": {
            "transmitter": {
                "spreading_factor": 7,
                "bandwidth_hz": 125000,
                "coding_rate_denominator": 5,
                "power_dbm": 0,
                "payload_length": 32,
                "preamble_symbols": 12,
                "crc_enabled": True,
                "iq_inverted": False,
            },
            "receiver": {"sample_rate_hz": 1000000},
            "bench": {"connection": "OTA"},
        },
        "transmissions": [{"index": 0, "radio_log": "TX state=0"}],
        "captures": [
            {
                "path": "capture/input.cf32",
                "bytes": len(samples),
                "sha256": digest,
            }
        ],
    }
    (run / "run.json").write_text(json.dumps(result), encoding="utf-8")
    sweep_result = {
        "cases": [
            {"name": name, "status": "complete", "run_directory": str(run)}
        ]
    }
    (sweep / "sweep-result.json").write_text(
        json.dumps(sweep_result), encoding="utf-8"
    )
    return sweep


def test_curate_verifies_and_copies_capture(tmp_path: Path) -> None:
    sweep = make_sweep(tmp_path)
    output = tmp_path / "reference"

    manifest = CURATOR.curate(CURATOR.completed_cases([sweep]), output)

    assert manifest["capture_count"] == 1
    assert manifest["total_bytes"] == 64
    assert (output / "sf7-bw125.cf32").read_bytes() == b"\x00\x00\x80?\x00\x00\x00\x00" * 8
    assert json.loads((output / "manifest.json").read_text(encoding="utf-8"))[
        "captures"
    ][0]["capture"]["samples"] == 8


def test_duplicate_completed_case_is_rejected(tmp_path: Path) -> None:
    first = make_sweep(tmp_path / "first")
    second = make_sweep(tmp_path / "second")

    with pytest.raises(ValueError, match="Duplicate completed case"):
        CURATOR.completed_cases([first, second])
