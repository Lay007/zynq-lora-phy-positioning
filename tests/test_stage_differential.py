"""Regression for the stage-by-stage receive-chain differential.

The synthetic fixtures build a complete SF7 frame, freeze a "perfect" PL trace
from it, and then damage exactly one stage at a time.  The tool has to name the
damaged stage and no earlier one, which is what makes it usable for localising
a defect rather than fitting a correction to it.
"""

import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

from zynq_lora_phy import (
    CssConfig,
    encode_lora_packet,
    fft_correlator_stages,
    modulate_symbol,
    reference_chirp,
)

from tools.export_stage_differential import (
    analyze,
    render_summary,
    write_csv,
    zlp1_payload,
)


CONFIG = CssConfig(spreading_factor=7, samples_per_chip=8)
SIZE = CONFIG.samples_per_symbol
PREAMBLE_SYMBOLS = 12
SYNC_SYMBOLS = 2
SFD_SYMBOLS = 2

SEQUENCE = 30
START_MS = 11849939
LENGTH = 32


def build_frame(payload: bytes) -> tuple[np.ndarray, int]:
    """Return a complete frame and the sample index of header symbol zero."""

    symbols = list(encode_lora_packet(payload, spreading_factor=7, coding_rate=1).symbols)
    upchirp = reference_chirp(CONFIG)
    downchirp = reference_chirp(CONFIG, up=False)

    # The header sits 2.25 downchirps past the sync word, which is the
    # geometry the tool assumes when it places its up/down search windows.
    parts = [upchirp] * PREAMBLE_SYMBOLS
    parts.extend(modulate_symbol(value, CONFIG) for value in (24, 32))
    parts.extend([downchirp] * SFD_SYMBOLS)
    parts.append(downchirp[: SIZE // 4])
    header_start = sum(part.size for part in parts)
    parts.extend(modulate_symbol(value, CONFIG) for value in symbols)

    frame = np.concatenate(parts)
    # The burst detector thresholds against the median of the whole capture,
    # so the frame has to stay a minority of it, exactly as in a real DMA
    # recording where one packet sits in 1.5 million samples.
    lead = 30 * SIZE
    trail = 90 * SIZE
    rng = np.random.default_rng(11)

    def noise(count: int) -> np.ndarray:
        return 0.001 * (
            rng.standard_normal(count) + 1j * rng.standard_normal(count)
        )

    capture = np.concatenate([noise(lead), frame, noise(trail)])
    return capture, lead + header_start


def write_iq(path: Path, iq: np.ndarray, scale: float = 120.0) -> None:
    scaled = iq * scale
    interleaved = np.empty(scaled.size * 2, dtype="<i2")
    interleaved[0::2] = np.round(scaled.real).astype("<i2")
    interleaved[1::2] = np.round(scaled.imag).astype("<i2")
    interleaved.tofile(path)


def build_trace(
    iq: np.ndarray,
    header_start: int,
    *,
    symbol_offset: int = 2,
    phase_offset: int = 0,
    entry_count: int = 64,
    conjugate_decisions: bool = False,
) -> dict:
    """Freeze a PL trace that agrees with the reference on its own windows."""

    first = header_start - symbol_offset * SIZE + phase_offset
    starts = first + np.arange(entry_count) * SIZE
    windows = np.stack([iq[start : start + SIZE] for start in starts])
    source = np.conjugate(windows) if conjugate_decisions else windows
    decisions = fft_correlator_stages(source, CONFIG).symbols

    entries = [
        {
            "index": index,
            "symbol": int(decisions[index]),
            # The PL counter runs in its own epoch; only differences matter.
            "sample_count": 1_000_000 + index * SIZE,
            "confidence_q15": 12000,
            "flags": 2,
        }
        for index in range(entry_count)
    ]
    return {
        "schema": "zynq-lora-clg400-symbol-trace-v1",
        "capture_sequence": 7,
        "preamble_bin": 0,
        "grid_phase_removed": 0,
        "captured_count": entry_count,
        "grid_realigned": True,
        "decode": {"symbol_offset": symbol_offset, "bin_adjustment": 0},
        "entries": entries,
        "serial": {
            "tx_sequence": SEQUENCE,
            "tx_start_ms": START_MS,
            "tx_payload_length": LENGTH,
        },
    }


@pytest.fixture
def fixture_paths(tmp_path: Path):
    def build(*, phase_offset: int = 0, conjugate_iq: bool = False, **kwargs):
        payload = zlp1_payload(SEQUENCE, START_MS, LENGTH)
        iq, header_start = build_frame(payload)
        if conjugate_iq:
            iq = np.conjugate(iq)
        trace = build_trace(
            iq,
            header_start,
            phase_offset=phase_offset,
            conjugate_decisions=conjugate_iq,
            **kwargs,
        )
        iq_path = tmp_path / "capture.bin"
        trace_path = tmp_path / "trace.json"
        write_iq(iq_path, iq)
        trace_path.write_text(json.dumps(trace), encoding="utf-8")
        return trace_path, iq_path

    return build


def test_zlp1_payload_matches_the_recorded_hardware_payload() -> None:
    # From docs/data/clg400-symbol-trace-2026-09-03.json, the accepted capture
    # whose decoded bytes the transmitter independently confirmed.
    assert (
        zlp1_payload(10, 2297116, 32).hex()
        == "5a4c50310a0000001c0d23000a0b0c0d0e0f101112131415161718191a1b1c1d"
    )


def test_zlp1_payload_rejects_a_frame_shorter_than_its_header() -> None:
    with pytest.raises(ValueError, match="twelve bytes"):
        zlp1_payload(1, 2, 8)


def test_an_undamaged_chain_reports_no_divergence(fixture_paths) -> None:
    trace_path, iq_path = fixture_paths()
    report = analyze(trace_path, iq_path)

    assert report.first_divergent_stage is None
    assert report.expected_symbols_available
    assert report.transmitter_sequence == SEQUENCE
    verdicts = {stage["stage"]: stage["verdict"] for stage in report.stages}
    assert verdicts["symbol"] == "agreed"
    assert verdicts["packet_decode"] == "agreed"
    # Every payload-determined symbol lands on its transmitted bin.
    assert report.bin_error_histogram == {"0": 53}


def test_a_sample_phase_offset_is_blamed_on_the_symbol_stage(fixture_paths) -> None:
    # Half a chip of grid error: the PL still agrees with the reference on its
    # own windows, so every upstream stage must stay clean and the symbol
    # stage must take the blame.
    trace_path, iq_path = fixture_paths(phase_offset=4)
    report = analyze(trace_path, iq_path)

    assert report.first_divergent_stage == "symbol"
    verdicts = {stage["stage"]: stage["verdict"] for stage in report.stages}
    for stage in ("raw_iq", "iq_format", "sample_grid", "reference_chirp"):
        assert verdicts[stage] == "agreed", stage
    assert verdicts["peak_bin"] in {"agreed", "tie-break"}
    # The signature that matters: a sub-chip grid error biases decisions one
    # way only.  This is the same shape the hardware captures show, and it is
    # what rules out a symmetric rounding or wrap defect.
    errors = {int(key): value for key, value in report.bin_error_histogram.items()}
    assert set(errors) == {0, 1}, errors
    assert errors[1] > 0
    # And the reason it can only be one-sided: a residual near the half-chip
    # decision boundary splits the packet across two adjacent bins, so the one
    # integer adjustment available is right for one group and wrong for the
    # other by exactly one bin.
    assert report.raw_decision_bin_spread == 2


def test_the_joint_correction_recovers_a_sample_phase_offset(fixture_paths) -> None:
    trace_path, iq_path = fixture_paths(phase_offset=4)
    report = analyze(trace_path, iq_path)

    by_stage = {stage["stage"]: stage for stage in report.stages}
    corrected = by_stage["symbol_timing_corrected"]
    assert corrected["verdict"] == "agreed"
    assert corrected["agreed"] == corrected["compared"] > 0
    assert by_stage["packet_decode"]["verdict"] == "agreed"
    assert report.joint_chirp_timing["correction_samples"] == -4


@pytest.mark.parametrize(
    "phase_offset, expected_sign", [(-6, -1), (-5, -1), (5, 1), (6, 1)]
)
def test_the_bias_direction_follows_the_sign_of_the_residual(
    fixture_paths, phase_offset: int, expected_sign: int
) -> None:
    """A sub-chip residual is not one-signed on its own.

    Beyond the half-chip boundary every symbol tips the same way, and the
    direction is the sign of the grid error.  The one-sidedness seen on
    hardware therefore comes from the integer adjustment absorbing one of two
    split groups, not from a signed defect inside the correlator.
    """

    trace_path, iq_path = fixture_paths(phase_offset=phase_offset)
    report = analyze(trace_path, iq_path)
    errors = {int(key): value for key, value in report.bin_error_histogram.items()}
    assert set(errors) == {expected_sign}, errors


def test_a_conjugated_stream_is_blamed_on_the_iq_format_stage(fixture_paths) -> None:
    trace_path, iq_path = fixture_paths(conjugate_iq=True)
    report = analyze(trace_path, iq_path)

    assert report.first_divergent_stage == "iq_format"
    assert "INVERTED" in report.first_divergent_detail


def test_without_a_transmitter_log_the_ladder_stops_at_the_peak_bin(
    tmp_path: Path,
) -> None:
    """A capture with no serial log still localises what it can.

    The expected-symbol rungs need the transmitter's own record.  Without it
    they must report "not compared" rather than silently passing, while the
    PL-against-reference rungs still run.
    """

    payload = zlp1_payload(SEQUENCE, START_MS, LENGTH)
    iq, header_start = build_frame(payload)
    trace = build_trace(iq, header_start)
    del trace["serial"]

    iq_path = tmp_path / "capture.bin"
    trace_path = tmp_path / "trace.json"
    write_iq(iq_path, iq)
    trace_path.write_text(json.dumps(trace), encoding="utf-8")

    report = analyze(trace_path, iq_path)
    assert not report.expected_symbols_available
    verdicts = {stage["stage"]: stage["verdict"] for stage in report.stages}
    assert verdicts["peak_bin"] == "agreed"
    for stage in ("symbol", "symbol_timing_corrected", "packet_decode"):
        assert verdicts[stage] == "not compared", stage
    assert all(row["expected_symbol"] == "" for row in report.rows)


def test_rows_expose_every_documented_pipeline_column(fixture_paths) -> None:
    trace_path, iq_path = fixture_paths()
    report = analyze(trace_path, iq_path)

    assert report.rows
    columns = set(report.rows[0])
    for name in (
        "pl_sample_count",
        "dma_window_start",
        "grid_window_start",
        "reference_phase_index",
        "window_mean_i",
        "window_mean_q",
        "dechirped_dc_i",
        "dechirped_dc_q",
        "dechirp_bin",
        "correlator_peak_power",
        "correlator_second_power",
        "reference_peak_bin",
        "reference_second_bin",
        "timing_correction_samples",
        "cfo_displacement_samples",
        "pl_raw_symbol",
        "pl_final_symbol",
        "corrected_final_symbol",
        "expected_symbol",
    ):
        assert name in columns, name


def test_the_csv_round_trips_every_row(fixture_paths, tmp_path: Path) -> None:
    trace_path, iq_path = fixture_paths()
    report = analyze(trace_path, iq_path)
    destination = tmp_path / "nested" / "stages.csv"
    write_csv(report, destination)

    lines = destination.read_text(encoding="utf-8").strip().splitlines()
    assert len(lines) == len(report.rows) + 1
    assert lines[0].split(",")[0] == "trace_index"


def test_the_summary_names_the_first_divergent_stage(fixture_paths) -> None:
    trace_path, iq_path = fixture_paths(phase_offset=4)
    summary = render_summary(analyze(trace_path, iq_path))
    assert "FIRST DIVERGENCE: symbol" in summary


def test_the_command_line_runs_from_a_checkout_and_writes_its_outputs(
    fixture_paths, tmp_path: Path
) -> None:
    """Run the tool the way the documentation tells a reader to run it.

    Invoking it as a script exercises the import bootstrap and the argument
    handling, neither of which the library-level tests touch.  The IQ path is
    omitted on purpose: the trace names its own capture.
    """

    trace_path, iq_path = fixture_paths(phase_offset=4)
    # The tool resolves serial.iq_capture beside the trace.
    trace = json.loads(trace_path.read_text(encoding="utf-8"))
    trace["serial"]["iq_capture"] = iq_path.name
    trace_path.write_text(json.dumps(trace), encoding="utf-8")

    csv_path = tmp_path / "out" / "stages.csv"
    json_path = tmp_path / "out" / "stages.json"
    repository_root = Path(__file__).resolve().parents[1]
    completed = subprocess.run(
        [
            sys.executable,
            str(repository_root / "tools" / "export_stage_differential.py"),
            str(trace_path),
            "--csv",
            str(csv_path),
            "--json",
            str(json_path),
        ],
        capture_output=True,
        text=True,
        cwd=repository_root,
    )

    # A divergent capture is a successful run that found something, and the
    # documented exit code for that is 1.
    assert completed.returncode == 1, completed.stderr
    assert "FIRST DIVERGENCE: symbol" in completed.stdout
    assert csv_path.is_file() and json_path.is_file()
    report = json.loads(json_path.read_text(encoding="utf-8"))
    assert report["schema"] == "zynq-lora-stage-differential-v1"
    assert report["first_divergent_stage"] == "symbol"


def test_a_short_trace_is_rejected(tmp_path: Path) -> None:
    trace_path = tmp_path / "short.json"
    trace_path.write_text(json.dumps({"entries": [{"index": 0}]}), encoding="utf-8")
    iq_path = tmp_path / "empty.bin"
    write_iq(iq_path, np.zeros(16, dtype=complex))
    with pytest.raises(ValueError, match="fewer than eight"):
        analyze(trace_path, iq_path)
