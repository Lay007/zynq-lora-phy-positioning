"""Counting rules of the capture-run summary (no hardware, no files)."""

from __future__ import annotations

from tools.summarize_capture_run import summarize


def _ok(crc: bool = True, straddle: bool = False, precise: bool = True) -> dict:
    return {
        "decode": {"crc_valid": crc},
        "joint_estimate": {
            "detector_straddle_accepted": straddle,
            "precise_correction_applied": precise,
        },
    }


def _failed(stage: str, burst: float | None = None) -> dict:
    record: dict = {"status": "failed", "stage": stage}
    if burst is not None:
        record["iq_burst_ratio"] = burst
    return record


def test_every_attempt_is_counted_and_failures_are_kept_apart() -> None:
    records = [
        _ok(),
        _ok(crc=False),
        _failed("read_trace", burst=4000.0),
        _failed("read_trace", burst=1.2),
        _failed("send"),
    ]

    summary = summarize(records)

    assert summary["attempts"] == 5
    assert summary["captured"] == 2
    assert summary["failed"] == 3
    assert summary["failed_by_stage"] == {"read_trace": 2, "send": 1}
    assert summary["crc_valid"] == "1/2 (50%)"


def test_a_trace_failure_with_a_strong_recording_is_a_detector_miss() -> None:
    summary = summarize(
        [_failed("read_trace", burst=4000.0), _failed("read_trace", burst=1.2)]
    )

    assert summary["undetected_but_packet_in_recording"] == 1
    assert summary["no_packet_in_recording"] == 1


def test_a_trace_failure_without_iq_is_neither() -> None:
    """Old failure records carry no burst ratio: do not guess."""

    summary = summarize([_failed("read_trace")])

    assert summary["undetected_but_packet_in_recording"] == 0
    assert summary["no_packet_in_recording"] == 0


def test_straddle_accepted_packets_are_reported_separately() -> None:
    records = [
        _ok(),
        _ok(),
        _ok(straddle=True),
        _ok(straddle=True, crc=False, precise=False),
    ]

    summary = summarize(records)

    assert summary["straddle_accepted"] == 2
    assert summary["straddle_accepted_crc_valid"] == "1/2 (50%)"
    assert summary["straddle_accepted_precise_applied"] == "1/2 (50%)"
    assert summary["not_straddle_crc_valid"] == "2/2 (100%)"


def test_an_empty_run_does_not_divide_by_zero() -> None:
    summary = summarize([])

    assert summary["attempts"] == 0
    assert summary["crc_valid"] == "0/0"
    assert summary["straddle_accepted_crc_valid"] == "0/0"
