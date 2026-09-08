"""Checks for the paired IQ/trace capture tool.

Most of the tool drives hardware, so these cover the parts that decide what the
board is asked to do. A wrong recording command is the failure that would
silently produce an unusable capture after a bench session has already been
spent.
"""

import pytest

from tools.capture_clg400_iq_trace_pair import (
    DEFAULT_IQ_SAMPLES,
    REMOTE_IQ,
    iio_capture_command,
    utc_stamp,
)


def test_the_default_recording_brackets_one_packet() -> None:
    # 1.5 s at 1 MS/s against an ~83 ms SF7 packet.
    assert DEFAULT_IQ_SAMPLES == 1_500_000
    assert DEFAULT_IQ_SAMPLES / 1_000_000 > 10 * 0.083


def test_the_recording_command_selects_both_iq_channels() -> None:
    command = iio_capture_command(DEFAULT_IQ_SAMPLES, REMOTE_IQ)
    # Both channels, or the analysis gets real samples instead of complex ones.
    assert "voltage0 voltage1" in command
    assert "cf-ad9361-lpc" in command
    assert f"-s {DEFAULT_IQ_SAMPLES}" in command


def test_the_recording_command_detaches_and_records_its_status() -> None:
    command = iio_capture_command(1000, REMOTE_IQ)
    # Detached, so the transmission can happen while the buffer fills.
    assert command.rstrip().endswith("&")
    # The exit status has to survive detaching or a failed recording looks
    # identical to a slow one.
    assert f"echo $? > {REMOTE_IQ}.done" in command
    # A stale recording or sentinel from a previous attempt must not be
    # mistaken for this one.
    assert command.startswith(f"rm -f {REMOTE_IQ} {REMOTE_IQ}.done;")


def test_the_recording_command_writes_where_the_caller_asked() -> None:
    command = iio_capture_command(64, "/tmp/other.bin")
    assert "> /tmp/other.bin" in command
    assert "/tmp/other.bin.done" in command


@pytest.mark.parametrize("samples", [0, -1])
def test_a_nonpositive_sample_count_is_rejected(samples: int) -> None:
    with pytest.raises(ValueError, match="positive"):
        iio_capture_command(samples, REMOTE_IQ)


def test_the_stamp_is_a_sortable_utc_basename() -> None:
    stamp = utc_stamp()
    assert stamp.endswith("Z") and "T" in stamp
    assert len(stamp) == len("20260908T065448Z")
    assert stamp.replace("T", "").replace("Z", "").isdigit()
