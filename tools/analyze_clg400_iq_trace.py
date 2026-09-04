#!/usr/bin/env python3
"""Compare a frozen CLG400 symbol trace with its simultaneous RX1 IQ capture.

The comparison uses the same two-FFT correlation identity as the generated
SF7/L=8 correlator, rather than the more common sample-wise dechirp shortcut.
It first aligns the trace timestamps to the DMA capture from the decisions
themselves.  It then evaluates small, explicit corrections to the resync skip
and reports which of them make the independently demodulated IQ pass the LoRa
header checksum, payload CRC, and (when present) the transmitter's ZLP1
sequence number.

The input IQ file is interleaved little-endian signed 16-bit I/Q.  No hardware
is accessed and the ignored raw capture is never copied into the report.
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterable

import numpy as np
from numpy.typing import NDArray

from zynq_lora_phy import CssConfig, decode_lora_packet, reference_chirp


ComplexArray = NDArray[np.complex128]
IntegerArray = NDArray[np.int64]


@dataclass(frozen=True)
class DecodeCandidate:
    bin_adjustment: int
    header_valid: bool
    crc_valid: bool
    consumed_symbol_count: int
    payload_hex: str
    payload_ascii: str
    zlp1_sequence: int | None
    zlp1_start_ms: int | None
    transmitter_sequence_matches: bool | None


def load_iq(path: Path) -> ComplexArray:
    """Load interleaved little-endian int16 I/Q without changing its scale."""

    raw = np.fromfile(path, dtype="<i2")
    if raw.size % 2:
        raise ValueError(f"IQ file has an odd int16 count: {path}")
    return (
        raw[0::2].astype(np.float64) + 1j * raw[1::2].astype(np.float64)
    ).astype(np.complex128, copy=False)


def fft_correlator_bins(
    iq: ComplexArray, starts: Iterable[int], config: CssConfig
) -> IntegerArray:
    """Return bins from the exact two-FFT identity used by the generated DUT."""

    starts_array = np.asarray(tuple(starts), dtype=np.int64)
    if starts_array.size == 0:
        return np.empty(0, dtype=np.int64)
    size = config.samples_per_symbol
    if np.any(starts_array < 0) or np.any(starts_array + size > iq.size):
        raise ValueError("a requested correlation window falls outside the IQ capture")

    windows = np.stack([iq[start : start + size] for start in starts_array])
    reference_spectrum = np.conjugate(np.fft.fft(reference_chirp(config)))
    product = np.fft.fft(windows, axis=1) * reference_spectrum
    # MATLAB reshapes each M-vector as N x L in column-major order.  Express
    # the same q=r+m*N frequency partition explicitly to avoid relying on a
    # language-specific reshape convention.
    partition = product.reshape(
        starts_array.size,
        config.samples_per_chip,
        config.symbol_count,
    ).sum(axis=1)
    magnitude = np.abs(np.fft.fft(partition, axis=1)) ** 2
    return np.argmax(magnitude, axis=1).astype(np.int64)


def burst_bounds(iq: ComplexArray, window: int = 1024) -> tuple[int, int]:
    """Find the strong packet interval with a robust power threshold."""

    power = np.abs(iq) ** 2
    smooth = np.convolve(power, np.ones(window) / window, mode="valid")
    floor = float(np.median(smooth))
    peak = float(np.max(smooth))
    threshold = floor + 0.25 * (peak - floor)
    above = np.flatnonzero(smooth > threshold)
    if above.size == 0:
        raise ValueError("no RF burst found in the IQ capture")
    return int(above[0]), int(above[-1])


def align_trace(
    iq: ComplexArray,
    entries: list[dict[str, object]],
    burst_start: int,
    config: CssConfig,
    *,
    compare_count: int = 24,
) -> tuple[int, int, int]:
    """Map trace sample counts to DMA indices by maximising raw-bin agreement."""

    selected = entries[: min(compare_count, len(entries))]
    if len(selected) < 4:
        raise ValueError("at least four trace entries are required for alignment")
    first_count = int(selected[0]["sample_count"])
    relative = np.asarray(
        [int(entry["sample_count"]) - first_count for entry in selected],
        dtype=np.int64,
    )
    observed = np.asarray([int(entry["symbol"]) for entry in selected])

    # The frozen trace begins with the two SFD decisions, approximately
    # fourteen symbols after the beginning of a twelve-symbol preamble.
    nominal = burst_start + 14 * config.samples_per_symbol
    coarse = range(nominal - 2048, nominal + 2049, config.samples_per_chip)

    def score(base: int) -> int:
        bins = fft_correlator_bins(iq, base + relative, config)
        return int(np.sum(bins == observed))

    coarse_base = max(coarse, key=score)
    fine = range(
        coarse_base - config.samples_per_chip,
        coarse_base + config.samples_per_chip + 1,
    )
    base = max(fine, key=score)
    return base, score(base), len(selected)


def decode_with_adjustment(
    raw_bins: Iterable[int],
    spreading_factor: int,
    adjustments: Iterable[int],
    transmitter_sequence: int | None,
) -> DecodeCandidate | None:
    """Return the first CRC-valid bounded bin-domain correction."""

    count = 1 << spreading_factor
    bins = tuple(int(value) for value in raw_bins)
    for adjustment in adjustments:
        corrected = [(value + adjustment) % count for value in bins]
        result = decode_lora_packet(corrected, spreading_factor=spreading_factor)
        if not result.success:
            continue
        payload = result.payload
        is_zlp1 = len(payload) >= 12 and payload[:4] == b"ZLP1"
        sequence = int.from_bytes(payload[4:8], "little") if is_zlp1 else None
        start_ms = int.from_bytes(payload[8:12], "little") if is_zlp1 else None
        sequence_matches = (
            None
            if transmitter_sequence is None or sequence is None
            else sequence == transmitter_sequence
        )
        if transmitter_sequence is not None and sequence_matches is not True:
            continue
        return DecodeCandidate(
            bin_adjustment=int(adjustment),
            header_valid=result.header_valid,
            crc_valid=result.crc_valid,
            consumed_symbol_count=result.consumed_symbol_count,
            payload_hex=payload.hex(),
            payload_ascii="".join(
                chr(value) if 32 <= value < 127 else "." for value in payload
            ),
            zlp1_sequence=sequence,
            zlp1_start_ms=start_ms,
            transmitter_sequence_matches=sequence_matches,
        )
    return None


def analyze(trace_path: Path, iq_path: Path) -> dict[str, object]:
    trace = json.loads(trace_path.read_text(encoding="utf-8"))
    entries = trace["entries"]
    if len(entries) < 4:
        raise ValueError("the trace contains fewer than four entries")

    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    iq = load_iq(iq_path)
    first, last = burst_bounds(iq)
    base, matches, compared = align_trace(iq, entries, first, config)

    sample_counts = [int(entry["sample_count"]) for entry in entries]
    gaps = [right - left for left, right in zip(sample_counts, sample_counts[1:])]
    largest_gap_index = int(np.argmax(gaps))
    skip_samples = gaps[largest_gap_index] - config.samples_per_symbol
    if skip_samples < 0:
        raise ValueError("trace sample counts moved backwards")

    # In the current trace ABI entry 2 is the transition affected by resync;
    # entry 3 is the first stable post-resync header decision.  Reconstruct
    # where header symbol zero would start on that new regular grid.
    relative_entry3 = sample_counts[3] - sample_counts[0]
    current_header_start = base + relative_entry3 - config.samples_per_symbol
    transmitter_sequence = trace.get("serial", {}).get("tx_sequence")
    if transmitter_sequence is not None:
        transmitter_sequence = int(transmitter_sequence)

    window_count = min(70, (iq.size - current_header_start) // config.samples_per_symbol)
    if window_count < 58:
        raise ValueError("not enough IQ remains after the inferred header start")

    adjustments = range(-32, 33)
    corrections: list[dict[str, object]] = []
    for correction_samples in range(-32, 33):
        start = current_header_start + correction_samples
        starts = start + np.arange(window_count) * config.samples_per_symbol
        raw_bins = fft_correlator_bins(iq, starts, config)
        decoded = decode_with_adjustment(
            raw_bins,
            config.spreading_factor,
            adjustments,
            transmitter_sequence,
        )
        if decoded is not None:
            corrections.append(
                {
                    "resync_correction_samples": correction_samples,
                    "resync_correction_chips": (
                        correction_samples / config.samples_per_chip
                    ),
                    "header_start_dma_sample": start,
                    "decode": asdict(decoded),
                }
            )

    return {
        "schema": "zynq-lora-clg400-iq-trace-comparison-v1",
        "trace_file": trace_path.name,
        "iq_file": iq_path.name,
        "iq_complex_samples": int(iq.size),
        "burst": {"first_sample": first, "last_sample": last},
        "trace_alignment": {
            "entry0_dma_sample": base,
            "raw_bin_matches": matches,
            "raw_bins_compared": compared,
        },
        "resync": {
            "largest_gap_after_entry": largest_gap_index,
            "skip_samples": skip_samples,
            "skip_chips": skip_samples / config.samples_per_chip,
            "current_header_start_dma_sample": current_header_start,
        },
        "transmitter_sequence": transmitter_sequence,
        "crc_valid_corrections": corrections,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path)
    parser.add_argument("iq", type=Path)
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        report = analyze(args.trace, args.iq)
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    rendered = json.dumps(report, indent=2, ensure_ascii=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
        print(f"saved {args.output}")

    alignment = report["trace_alignment"]
    resync = report["resync"]
    print(
        f"trace/IQ raw-bin agreement: {alignment['raw_bin_matches']}/"
        f"{alignment['raw_bins_compared']}; resync skip: "
        f"{resync['skip_samples']} samples"
    )
    corrections = report["crc_valid_corrections"]
    matching = [
        item
        for item in corrections
        if item["decode"]["transmitter_sequence_matches"] is not False
    ]
    print(
        "CRC-valid resync corrections (samples): "
        + (
            ", ".join(str(item["resync_correction_samples"]) for item in matching)
            or "none"
        )
    )
    return 0 if matching else 1


if __name__ == "__main__":
    raise SystemExit(main())
