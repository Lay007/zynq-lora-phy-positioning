"""Generate deterministic Q10 vectors for the packet-rate matched filter RTL."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np

from zynq_lora_phy import CssConfig, reference_chirp


SF = 7
SAMPLES_PER_CHIP = 8
Q_FRACTION_BITS = 10
SEARCH_RADIUS = 8
POWER_SHIFT = 30


def quantize_q10(values: np.ndarray) -> np.ndarray:
    """Round like the SystemVerilog tests and saturate to signed int16."""

    scaled = np.where(
        values >= 0.0,
        np.floor(values * (1 << Q_FRACTION_BITS) + 0.5),
        np.ceil(values * (1 << Q_FRACTION_BITS) - 0.5),
    )
    return np.clip(scaled, -32768, 32767).astype(np.int16)


def packed_words(iq: np.ndarray) -> list[int]:
    re = quantize_q10(iq.real).astype(np.uint16).astype(np.uint32)
    im = quantize_q10(iq.imag).astype(np.uint16).astype(np.uint32)
    return ((re << 16) | im).tolist()


def correlation_powers(stimulus_words: list[int], reference_words: list[int]) -> list[int]:
    def signed16(value: int) -> int:
        value &= 0xFFFF
        return value - 0x10000 if value & 0x8000 else value

    samples = [
        (signed16(word >> 16), signed16(word)) for word in stimulus_words
    ]
    reference = [
        (signed16(word >> 16), signed16(word)) for word in reference_words
    ]
    powers: list[int] = []
    for lag in range(2 * SEARCH_RADIUS + 1):
        acc_re = 0
        acc_im = 0
        for (x_re, x_im), (r_re, r_im) in zip(
            samples[lag : lag + len(reference)], reference, strict=True
        ):
            acc_re += x_re * r_re + x_im * r_im
            acc_im += x_im * r_re - x_re * r_im
        power = (acc_re * acc_re + acc_im * acc_im) >> POWER_SHIFT
        powers.append(min(power, 0xFFFF_FFFF))
    return powers


def write_hex(path: Path, words: list[int], width: int = 8) -> str:
    payload = "".join(f"{word:0{width}x}\n" for word in words)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(payload, encoding="ascii", newline="\n")
    return hashlib.sha256(payload.encode("ascii")).hexdigest()


def main() -> None:
    root = Path(__file__).resolve().parents[1]
    config = CssConfig(spreading_factor=SF, samples_per_chip=SAMPLES_PER_CHIP)
    reference_words = packed_words(reference_chirp(config))
    zero = [0] * SEARCH_RADIUS
    stimulus_words = zero + reference_words + zero
    powers = correlation_powers(stimulus_words, reference_words)

    reference_path = root / "fpga/rom/lora_sf7_l8_reference_q10.mem"
    stimulus_path = root / "fpga/tb/vectors/lora_sf7_l8_matched_filter_stimulus_q10.mem"
    power_path = root / "fpga/tb/vectors/lora_sf7_l8_matched_filter_power.mem"

    manifest = {
        "schema": "zynq-lora-matched-filter-rtl-v1",
        "spreading_factor": SF,
        "samples_per_chip": SAMPLES_PER_CHIP,
        "reference_samples": len(reference_words),
        "q_fraction_bits": Q_FRACTION_BITS,
        "search_radius": SEARCH_RADIUS,
        "power_shift": POWER_SHIFT,
        "coarse_start_count": SEARCH_RADIUS,
        "expected_peak_index": int(np.argmax(powers)),
        "expected_peak_sample_count": int(np.argmax(powers)),
        "reference_sha256": write_hex(reference_path, reference_words),
        "stimulus_sha256": write_hex(stimulus_path, stimulus_words),
        "power_sha256": write_hex(power_path, powers),
        "expected_power": powers,
    }
    manifest_path = root / "fpga/tb/vectors/lora_sf7_l8_matched_filter_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    print(manifest_path)


if __name__ == "__main__":
    main()

