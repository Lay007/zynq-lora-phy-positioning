#!/usr/bin/env python3
"""Differential regression across the LoRa receive chain, stage by stage.

For one raw IQ capture and the PL symbol trace frozen from the *same* packet,
this walks the documented pipeline

    raw IQ -> I/Q format -> sample grid -> reference chirp -> dechirp
           -> correlator powers -> peak bin -> timing/CFO -> symbol -> packet

and reports, for every stage, whether the reference model and the PL agree.
The point is to name the **first** stage at which they stop agreeing, so a
defect is localised rather than compensated with a fitted bin offset.

Three independent symbol sources are compared per window:

``pl``
    the decision the programmable logic froze into its trace;
``reference``
    the two-FFT correlator identity evaluated on the PL's own sample window;
``expected``
    the symbols the transmitter must have sent, rebuilt from the serial log
    through the packet encoder.  This never looks at the received IQ, so it
    cannot absorb a receiver defect.

The expected side is available only for the deterministic ``ZLP1`` counter
frame documented in ``firmware/heltec-v4-sx1262-tx``.  Without it the tool
still compares ``pl`` against ``reference`` and stops the ladder there.

The IQ file is interleaved little-endian signed 16-bit I/Q.  No hardware is
accessed and the raw capture is never copied into the report.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np
from numpy.typing import NDArray

from zynq_lora_phy import (
    CssConfig,
    decode_lora_packet,
    encode_lora_packet,
    estimate_joint_chirp_timing,
    fft_correlator_stages,
    reference_chirp,
)

try:  # running as `python -m tools...`, or imported by the test suite
    from tools.analyze_clg400_iq_trace import align_trace, burst_bounds, load_iq
except ModuleNotFoundError:  # running the file directly from a checkout
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
    from tools.analyze_clg400_iq_trace import align_trace, burst_bounds, load_iq


ComplexArray = NDArray[np.complex128]

# The ladder is ordered.  The first entry whose verdict is "diverged" is the
# stage the report blames; later stages are still measured and reported, but
# a failure there is a consequence, not a cause.
STAGE_ORDER = (
    "raw_iq",
    "iq_format",
    "sample_grid",
    "reference_chirp",
    "dechirp",
    "correlator_power",
    "peak_bin",
    "timing_cfo",
    "symbol",
    "symbol_timing_corrected",
    "packet_decode",
)

ZLP1_HEADER_LENGTH = 12


@dataclass
class StageVerdict:
    """One rung of the ladder.

    ``ambiguous`` counts windows where the two sides picked different bins but
    the disagreeing side chose the other's runner-up.  A correlator peak that
    only just clears its neighbour cannot be resolved consistently by two
    different implementations, so a swap there is a tie-break rather than a
    divergence.  Only a decision outside the reference top two proves the two
    sides computed different spectra.
    """

    stage: str
    verdict: str
    compared: int
    agreed: int
    detail: str
    ambiguous: int = 0

    @property
    def diverged(self) -> bool:
        return self.verdict == "diverged"


@dataclass
class DifferentialReport:
    schema: str = "zynq-lora-stage-differential-v1"
    trace_file: str = ""
    iq_file: str = ""
    spreading_factor: int = 7
    samples_per_chip: int = 8
    transmitter_sequence: int | None = None
    expected_symbols_available: bool = False
    packet_window_count: int = 0
    padding_dependent_symbol_count: int = 0
    excluded_transition_entries: list[int] = field(default_factory=list)
    pre_header_entries_excluded: int = 0
    first_divergent_stage: str | None = None
    first_divergent_detail: str = ""
    stages: list[dict[str, object]] = field(default_factory=list)
    alignment: dict[str, object] = field(default_factory=dict)
    joint_chirp_timing: dict[str, object] = field(default_factory=dict)
    bin_error_histogram: dict[str, int] = field(default_factory=dict)
    raw_bin_error_histogram: dict[str, int] = field(default_factory=dict)
    raw_decision_bin_spread: int = 0
    rows: list[dict[str, object]] = field(default_factory=list)


def zlp1_payload(sequence: int, start_ms: int, length: int) -> bytes:
    """Rebuild the deterministic Heltec counter frame from the serial log.

    The layout is fixed by ``firmware/heltec-v4-sx1262-tx``: ASCII magic, an
    unsigned little-endian sequence, the transmitter's ``millis()``, then a
    byte pattern that counts up from the sequence number.
    """

    if length < ZLP1_HEADER_LENGTH:
        raise ValueError("a ZLP1 frame is at least twelve bytes")
    body = bytes(
        (sequence + index) & 0xFF for index in range(length - ZLP1_HEADER_LENGTH)
    )
    return (
        b"ZLP1"
        + int(sequence).to_bytes(4, "little")
        + int(start_ms).to_bytes(4, "little")
        + body
    )


def dechirp_bins(windows: ComplexArray, config: CssConfig) -> NDArray[np.int64]:
    """Demodulate by sample-wise dechirp, the path independent of the DUT."""

    dechirped = windows * np.conjugate(reference_chirp(config))
    chip_rate = dechirped[:, :: config.samples_per_chip]
    power = np.abs(np.fft.fft(chip_rate, axis=1)) ** 2
    return np.argmax(power, axis=1).astype(np.int64)


def _verdict(
    agreed: int, compared: int, detail: str, *, ambiguous: int = 0
) -> StageVerdict:
    if compared == 0:
        return StageVerdict("", "not compared", 0, 0, detail)
    if agreed == compared:
        state = "agreed"
    elif agreed + ambiguous == compared:
        state = "tie-break"
    else:
        state = "diverged"
    return StageVerdict("", state, compared, agreed, detail, ambiguous)


def _named(stage: str, verdict: StageVerdict) -> StageVerdict:
    verdict.stage = stage
    return verdict


def analyze(
    trace_path: Path, iq_path: Path, *, compare_count: int = 24
) -> DifferentialReport:
    trace = json.loads(trace_path.read_text(encoding="utf-8"))
    entries = trace["entries"]
    if len(entries) < 8:
        raise ValueError("the trace contains fewer than eight entries")

    config = CssConfig(spreading_factor=7, samples_per_chip=8)
    size = config.samples_per_symbol
    count = config.symbol_count

    iq = load_iq(iq_path)
    report = DifferentialReport(
        trace_file=trace_path.name,
        iq_file=iq_path.name,
        spreading_factor=config.spreading_factor,
        samples_per_chip=config.samples_per_chip,
    )
    stages: list[StageVerdict] = []
    verdicts: dict[str, StageVerdict] = {}

    # ---- stage: raw IQ -------------------------------------------------
    peak_magnitude = float(np.max(np.abs(iq))) if iq.size else 0.0
    clipped = int(np.sum(np.abs(iq.real) >= 32767) + np.sum(np.abs(iq.imag) >= 32767))
    verdicts["raw_iq"] = _verdict(
        int(iq.size > 0 and peak_magnitude > 0.0 and clipped == 0),
        1,
        f"{iq.size} complex samples, peak |IQ| {peak_magnitude:.0f}, "
        f"{clipped} clipped components",
    )

    first, last = burst_bounds(iq)
    base, matches, compared = align_trace(
        iq, entries, first, config, compare_count=compare_count
    )
    report.alignment = {
        "burst_first_sample": first,
        "burst_last_sample": last,
        "entry0_dma_sample": base,
        "raw_bin_matches": matches,
        "raw_bins_compared": compared,
    }

    sample_counts = [int(entry["sample_count"]) for entry in entries]
    starts = np.asarray(
        [base + value - sample_counts[0] for value in sample_counts], dtype=np.int64
    )
    usable = int(np.sum((starts >= 0) & (starts + size <= iq.size)))
    if usable < 8:
        raise ValueError("fewer than eight trace windows fall inside the capture")
    starts = starts[:usable]

    # ---- stage: sample grid ---------------------------------------------
    gaps = np.diff(sample_counts[:usable])
    regular = int(np.sum(gaps == size))
    irregular = [
        {"after_entry": index, "gap_samples": int(gap), "skip_samples": int(gap - size)}
        for index, gap in enumerate(gaps)
        if gap != size
    ]
    # The integer-chip build makes one resync request. The joint-grid build
    # makes two: a coarse one that withholds FINE_GUARD_SAMPLES, and a late
    # fine one that returns the guard together with the signed correction.
    # More than two means the grid moved where it should not have.
    verdicts["sample_grid"] = _verdict(
        int(len(irregular) <= 2),
        1,
        f"{regular}/{len(gaps)} gaps equal one symbol; "
        f"{len(irregular)} resync skip(s), total "
        f"{sum(item['skip_samples'] for item in irregular)} samples: {irregular}",
    )

    # The entries before the resync sit on the old grid, so the receiver's
    # post-resync grid has to be reconstructed from the first entry after it.
    anchor = (irregular[-1]["after_entry"] + 1) if irregular else 0
    anchor = min(anchor, usable - 1)
    grid_starts = starts[anchor] + (np.arange(usable) - anchor) * size

    # ---- expected symbols, rebuilt from the transmitter's own log --------
    serial = trace.get("serial") or {}
    sequence = serial.get("tx_sequence")
    start_ms = serial.get("tx_start_ms")
    length = serial.get("tx_payload_length")
    expected: list[int] = []
    determined = 0
    if sequence is not None and start_ms is not None and length is not None:
        payload = zlp1_payload(int(sequence), int(start_ms), int(length))
        encoded = encode_lora_packet(
            payload, spreading_factor=config.spreading_factor, coding_rate=1
        )
        expected = list(encoded.symbols)
        # The last block carries padding nibbles whose value the payload does
        # not fix, and interleaving spreads them over every symbol of that
        # block.  Those symbols are reported but never counted as divergence.
        determined = encoded.payload_determined_symbol_count
        report.transmitter_sequence = int(sequence)
        report.expected_symbols_available = True
        report.padding_dependent_symbol_count = len(expected) - determined

    grid_phase = int(trace.get("grid_phase_removed", 0) or 0)
    decode_block = trace.get("decode") or {}
    symbol_offset = int(decode_block.get("symbol_offset", 0) or 0)
    bin_adjustment = int(decode_block.get("bin_adjustment", 0) or 0)

    # Per-window stages are only meaningful where a packet is present.  The
    # trace keeps running into noise after the packet ends, and comparing
    # decisions taken on noise measures nothing.
    packet_end = min(
        usable, symbol_offset + len(expected) if expected else compare_count
    )
    packet_end = max(packet_end, min(usable, compare_count))
    report.packet_window_count = packet_end

    windows = np.stack([iq[start : start + size] for start in starts[:packet_end]])
    upright = fft_correlator_stages(windows, config)
    two_fft = upright.symbols

    # At the entry the resync skip follows, the PL decided on samples it then
    # discarded, so its window and the reference window are provably different
    # samples.  That entry is reported but is not a valid comparison point.
    transition_entries = {
        item["after_entry"] for item in irregular if item["after_entry"] < packet_end
    }
    report.excluded_transition_entries = sorted(transition_entries)
    comparable = np.asarray(
        [index not in transition_entries for index in range(packet_end)], dtype=bool
    )
    # The entries before the header are SFD downchirps read with the upchirp
    # reference. Both sides do the same thing there and neither gets a
    # coherent peak, so the argmax is decided by tenths of a decibel and
    # comparing it measures nothing. Every rung that compares decisions is
    # scoped to windows that actually carry an upchirp symbol.
    upchirp_window = comparable & (np.arange(packet_end) >= symbol_offset)
    report.pre_header_entries_excluded = int(min(symbol_offset, packet_end))

    # ---- stage: I/Q format ----------------------------------------------
    # A conjugated or swapped stream correlates against the downchirp instead
    # of the upchirp, so comparing the two tests polarity without assuming
    # which convention the front end used.
    mirrored = fft_correlator_stages(np.conjugate(windows), config)
    upright_power = float(np.median(upright.peak_power))
    mirrored_power = float(np.median(mirrored.peak_power))
    verdicts["iq_format"] = _verdict(
        int(upright_power > mirrored_power),
        1,
        f"median upchirp peak {upright_power:.4g} vs conjugated "
        f"{mirrored_power:.4g} over {packet_end} packet windows; polarity is "
        + ("normal" if upright_power > mirrored_power else "INVERTED"),
    )

    # ---- stage: reference chirp ------------------------------------------
    reference_phase = (starts[:packet_end] % size).astype(np.int64)
    reference_energy = float(np.sum(np.abs(reference_chirp(config)) ** 2))
    verdicts["reference_chirp"] = _verdict(
        int(math.isclose(reference_energy, size, rel_tol=1e-9)),
        1,
        f"unit-amplitude reference holds {reference_energy:.1f} of {size} "
        f"expected energy; window phases span "
        f"{int(reference_phase.min())}..{int(reference_phase.max())}",
    )

    # ---- stage: dechirp ---------------------------------------------------
    sample_wise = dechirp_bins(windows, config)
    dechirp_agree = (sample_wise == two_fft) & upchirp_window
    dechirp_tie = (
        (sample_wise == upright.second_symbols) & upchirp_window & ~dechirp_agree
    )
    verdicts["dechirp"] = _verdict(
        int(np.sum(dechirp_agree)),
        int(np.sum(upchirp_window)),
        ambiguous=int(np.sum(dechirp_tie)),
        detail=(
            "sample-wise dechirp against the two-FFT correlator identity on "
            "identical upchirp windows; decimation and the aliasing sum are "
            "different operations off the symbol grid, so a smeared window "
            "can swap two near-equal bins"
        ),
    )

    # ---- stage: correlator powers -----------------------------------------
    margin_db = 10.0 * np.log10(
        np.maximum(upright.peak_power, 1e-30) / np.maximum(upright.second_power, 1e-30)
    )
    pl_raw = np.asarray(
        [int(entry["symbol"]) for entry in entries[:packet_end]], dtype=np.int64
    )
    # A PL decision that is neither the reference peak nor its runner-up is a
    # correlator-level disagreement, not a sample-phase one.  This is the
    # threshold-free form of "are both sides looking at the same spectrum".
    in_top_two = (pl_raw == two_fft) | (pl_raw == upright.second_symbols)
    verdicts["correlator_power"] = _verdict(
        int(np.sum(in_top_two & upchirp_window)),
        int(np.sum(upchirp_window)),
        "PL decisions that are the reference peak or its runner-up on upchirp "
        "windows; median peak-to-runner-up margin "
        f"{float(np.median(margin_db[upchirp_window])):.2f} dB",
    )

    # ---- stage: peak bin ---------------------------------------------------
    peak_agree = (pl_raw == two_fft) & upchirp_window
    peak_tie = (pl_raw == upright.second_symbols) & upchirp_window & ~peak_agree
    tie_margins = margin_db[peak_tie]
    verdicts["peak_bin"] = _verdict(
        int(np.sum(peak_agree)),
        int(np.sum(upchirp_window)),
        ambiguous=int(np.sum(peak_tie)),
        detail=(
            "PL frozen decisions against the reference correlator evaluated "
            "on the PL's own upchirp sample windows"
            + (
                "; runner-up swaps at margins "
                + ", ".join(f"{value:.2f} dB" for value in tie_margins)
                if tie_margins.size
                else ""
            )
        ),
    )

    # ---- stage: timing / CFO -----------------------------------------------
    # Both coarse starts come from the trace geometry on the reconstructed
    # grid, never from a payload scan, so this estimate is independent of the
    # decoded bits.
    header_start = int(grid_starts[symbol_offset]) if symbol_offset < usable else int(
        grid_starts[0]
    )
    header_from_packet = (12 + 2 + 2) * size + size // 4
    packet_start = header_start - header_from_packet
    joint = None
    joint_detail = "not evaluated"
    try:
        joint = estimate_joint_chirp_timing(
            iq,
            packet_start + 6 * size,
            packet_start + 14 * size,
            config,
            search_radius=32,
        )
        joint_detail = (
            f"timing {joint.timing_offset_samples:+.3f} samples -> "
            f"{joint.correction_samples:+d}; CFO displacement "
            f"{joint.cfo_displacement_samples:+.3f} samples"
        )
        report.joint_chirp_timing = asdict(joint)
    except ValueError as error:
        joint_detail = f"search window outside the capture: {error}"
    verdicts["timing_cfo"] = _verdict(int(joint is not None), 1, joint_detail)

    def normalise(bins: NDArray[np.int64], adjustment: int) -> NDArray[np.int64]:
        return (bins - grid_phase - adjustment) % count

    pl_final = normalise(pl_raw, bin_adjustment)
    reference_final = normalise(two_fft, bin_adjustment)

    # The expected-symbol comparison runs on the reconstructed receiver grid,
    # with and without the joint sample correction applied to it.
    def bins_at(offset: int) -> NDArray[np.int64]:
        shifted = grid_starts[:packet_end] + offset
        valid = (shifted >= 0) & (shifted + size <= iq.size)
        result = np.full(packet_end, -1, dtype=np.int64)
        if np.any(valid):
            stack = np.stack([iq[start : start + size] for start in shifted[valid]])
            result[valid] = fft_correlator_stages(stack, config).symbols
        return result

    grid_bins = bins_at(0)
    grid_final = np.where(grid_bins >= 0, normalise(grid_bins, bin_adjustment), -1)
    if joint is not None:
        corrected_bins = bins_at(joint.correction_samples)
        corrected_final = np.where(corrected_bins >= 0, normalise(corrected_bins, 0), -1)
    else:
        corrected_bins = np.full(packet_end, -1, dtype=np.int64)
        corrected_final = np.full(packet_end, -1, dtype=np.int64)

    # ---- stage: symbol -------------------------------------------------------
    expected_by_entry: dict[int, int] = {
        symbol_offset + index: value for index, value in enumerate(expected)
    }
    determined_entries = {
        symbol_offset + index for index in range(determined)
    }
    symbol_compared = symbol_agreed = 0
    corrected_compared = corrected_agreed = 0
    bias_histogram: dict[int, int] = {}
    raw_histogram: dict[int, int] = {}
    for index in range(packet_end):
        want = expected_by_entry.get(index)
        if want is None or index not in determined_entries:
            continue
        symbol_compared += 1
        symbol_agreed += int(pl_final[index] == want)
        error = int((int(pl_final[index]) - want + count // 2) % count - count // 2)
        bias_histogram[error] = bias_histogram.get(error, 0) + 1
        raw_error = int((int(pl_raw[index]) - want + count // 2) % count - count // 2)
        raw_histogram[raw_error] = raw_histogram.get(raw_error, 0) + 1
        if corrected_final[index] >= 0:
            corrected_compared += 1
            corrected_agreed += int(corrected_final[index] == want)

    # How many distinct bins the raw decisions land on, counting only errors
    # that occur more than once.  A residual sitting near the half-chip
    # decision boundary splits the packet across two adjacent bins; no single
    # integer bin adjustment can then be right for both groups, so whichever
    # one the decoder absorbs leaves the other wrong by exactly one bin, in
    # one direction.  That, not a signed arithmetic defect, is why the
    # surviving errors are one-sided.
    populated = sorted(key for key, value in raw_histogram.items() if value > 1)
    report.raw_bin_error_histogram = {
        str(key): value
        for key, value in sorted(raw_histogram.items(), key=lambda i: (-i[1], i[0]))
    }
    report.raw_decision_bin_spread = (
        populated[-1] - populated[0] + 1 if populated else 0
    )

    ordered_bias = dict(
        sorted(bias_histogram.items(), key=lambda item: (-item[1], item[0]))
    )
    report.bin_error_histogram = {str(key): value for key, value in ordered_bias.items()}
    verdicts["symbol"] = _verdict(
        symbol_agreed,
        symbol_compared,
        "PL symbols as delivered against the rebuilt transmitted symbols; "
        f"bin-error histogram {ordered_bias}",
    )
    verdicts["symbol_timing_corrected"] = _verdict(
        corrected_agreed,
        corrected_compared,
        "the same comparison after applying the joint up/down sample "
        "correction to the reconstructed symbol grid",
    )

    # ---- stage: packet decode -------------------------------------------------
    decode_detail = "no corrected grid available"
    decode_ok = decode_total = 0
    if corrected_compared:
        decode_total = 1
        corrected_symbols = [
            int(value) for value in corrected_final[symbol_offset:] if value >= 0
        ]
        result = decode_lora_packet(
            corrected_symbols, spreading_factor=config.spreading_factor
        )
        decode_ok = int(result.success)
        expected_payload = (
            zlp1_payload(int(sequence), int(start_ms), int(length))
            if report.expected_symbols_available
            else None
        )
        decode_detail = (
            f"header_valid={result.header_valid} crc_valid={result.crc_valid} "
            f"payload_matches_transmitter="
            f"{result.payload == expected_payload} "
            f"payload={result.payload.hex()}"
        )
    verdicts["packet_decode"] = _verdict(decode_ok, decode_total, decode_detail)

    for name in STAGE_ORDER:
        if name in verdicts:
            stages.append(_named(name, verdicts[name]))

    # ---- ladder verdict ---------------------------------------------------
    by_name = {item.stage: item for item in stages}
    report.stages = [asdict(item) for item in stages]
    for name in STAGE_ORDER:
        item = by_name.get(name)
        if item is not None and item.diverged:
            report.first_divergent_stage = name
            report.first_divergent_detail = item.detail
            break

    # ---- per-window rows --------------------------------------------------
    window_mean = windows.mean(axis=1)
    window_rms = np.sqrt(np.mean(np.abs(windows) ** 2, axis=1))
    dechirped = windows * np.conjugate(reference_chirp(config))
    dechirp_dc = dechirped.mean(axis=1)
    for index in range(packet_end):
        want = expected_by_entry.get(index)
        row: dict[str, object] = {
            "trace_index": index,
            "pl_sample_count": sample_counts[index],
            "dma_window_start": int(starts[index]),
            "grid_window_start": int(grid_starts[index]),
            "reference_phase_index": int(reference_phase[index]),
            "window_mean_i": float(window_mean[index].real),
            "window_mean_q": float(window_mean[index].imag),
            "window_rms": float(window_rms[index]),
            "dechirped_dc_i": float(dechirp_dc[index].real),
            "dechirped_dc_q": float(dechirp_dc[index].imag),
            "dechirp_bin": int(sample_wise[index]),
            "correlator_peak_power": float(upright.peak_power[index]),
            "correlator_second_power": float(upright.second_power[index]),
            "correlator_margin_db": float(margin_db[index]),
            "correlator_confidence": float(upright.confidence[index]),
            "reference_peak_bin": int(two_fft[index]),
            "reference_second_bin": int(upright.second_symbols[index]),
            "pl_confidence_q15": int(entries[index].get("confidence_q15", 0)),
            "pl_flags": int(entries[index].get("flags", 0)),
            "timing_correction_samples": (
                joint.correction_samples if joint is not None else ""
            ),
            "cfo_displacement_samples": (
                round(joint.cfo_displacement_samples, 6) if joint is not None else ""
            ),
            "pl_raw_symbol": int(pl_raw[index]),
            "pl_final_symbol": int(pl_final[index]),
            "reference_final_symbol": int(reference_final[index]),
            "grid_final_symbol": (
                int(grid_final[index]) if grid_final[index] >= 0 else ""
            ),
            "corrected_final_symbol": (
                int(corrected_final[index]) if corrected_final[index] >= 0 else ""
            ),
            "expected_symbol": want if want is not None else "",
            "pl_matches_reference": int(pl_raw[index] == two_fft[index]),
            "pl_matches_expected": (
                int(pl_final[index] == want) if want is not None else ""
            ),
            "corrected_matches_expected": (
                int(corrected_final[index] == want)
                if want is not None and corrected_final[index] >= 0
                else ""
            ),
            "pl_bin_error": (
                int((int(pl_final[index]) - want + count // 2) % count - count // 2)
                if want is not None
                else ""
            ),
        }
        report.rows.append(row)

    return report


def write_csv(report: DifferentialReport, path: Path) -> None:
    if not report.rows:
        raise ValueError("the report holds no rows to write")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(report.rows[0]))
        writer.writeheader()
        writer.writerows(report.rows)


def render_summary(report: DifferentialReport) -> str:
    lines = [f"{report.trace_file} + {report.iq_file}"]
    for stage in report.stages:
        compared = stage["compared"]
        agreed = stage["agreed"]
        share = f"{agreed}/{compared}" if compared else "-"
        ambiguous = stage.get("ambiguous", 0)
        note = f"  (+{ambiguous} tie-break)" if ambiguous else ""
        lines.append(
            f"  {stage['stage']:<24} {stage['verdict']:<12} {share}{note}"
        )
    if report.first_divergent_stage:
        lines.append(f"FIRST DIVERGENCE: {report.first_divergent_stage}")
        lines.append(f"  {report.first_divergent_detail}")
    else:
        lines.append("FIRST DIVERGENCE: none; every compared stage agreed")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("trace", type=Path, help="frozen PL symbol trace JSON")
    parser.add_argument(
        "iq",
        type=Path,
        nargs="?",
        help="interleaved int16 IQ capture; defaults to serial.iq_capture",
    )
    parser.add_argument("--csv", type=Path, help="write the per-window table here")
    parser.add_argument("--json", type=Path, help="write the full report here")
    parser.add_argument(
        "--compare-count",
        type=int,
        default=24,
        help="trace entries used to align the trace to the DMA epoch",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    trace_path = args.trace
    iq_path = args.iq
    if iq_path is None:
        try:
            trace = json.loads(trace_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"ERROR: {error}", file=sys.stderr)
            return 2
        name = (trace.get("serial") or {}).get("iq_capture")
        if not name:
            print("ERROR: no IQ path given and the trace names none", file=sys.stderr)
            return 2
        iq_path = trace_path.parent / name

    try:
        report = analyze(trace_path, iq_path, compare_count=args.compare_count)
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    if args.csv:
        write_csv(report, args.csv)
        print(f"saved {args.csv}")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(
            json.dumps(asdict(report), indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"saved {args.json}")

    print(render_summary(report))
    return 0 if report.first_divergent_stage is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
