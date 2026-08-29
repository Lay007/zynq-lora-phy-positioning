from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np

from zynq_lora_phy import CssConfig, reference_chirp


ROOT = Path(__file__).resolve().parents[1]
GENERATOR_PATH = ROOT / "tools/generate_sf7_l8_matched_filter_vectors.py"
MANIFEST_PATH = (
    ROOT / "fpga/tb/vectors/lora_sf7_l8_matched_filter_manifest.json"
)


def load_generator():
    spec = importlib.util.spec_from_file_location("matched_filter_vectors", GENERATOR_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_words(path: Path) -> list[int]:
    return [int(line, 16) for line in path.read_text(encoding="ascii").splitlines()]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_committed_sf7_l8_matched_filter_vectors_match_model() -> None:
    generator = load_generator()
    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    reference_path = ROOT / "fpga/rom/lora_sf7_l8_reference_q10.mem"
    stimulus_path = (
        ROOT / "fpga/tb/vectors/lora_sf7_l8_matched_filter_stimulus_q10.mem"
    )
    power_path = ROOT / "fpga/tb/vectors/lora_sf7_l8_matched_filter_power.mem"

    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    expected_reference = generator.packed_words(reference_chirp(config))
    expected_stimulus = [0] * 8 + expected_reference + [0] * 8
    expected_power = generator.correlation_powers(
        expected_stimulus, expected_reference
    )

    assert read_words(reference_path) == expected_reference
    assert read_words(stimulus_path) == expected_stimulus
    assert read_words(power_path) == expected_power
    assert manifest["expected_power"] == expected_power
    assert manifest["expected_peak_index"] == int(np.argmax(expected_power)) == 8
    assert manifest["reference_sha256"] == sha256(reference_path)
    assert manifest["stimulus_sha256"] == sha256(stimulus_path)
    assert manifest["power_sha256"] == sha256(power_path)

