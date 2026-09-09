import pytest

from tools.read_clg400_symbol_trace import (
    ClockAccounting,
    _clock_summary,
    grid_phase,
    parse_trace,
)
from tools.run_clg400_payload_capture import (
    parse_profile,
    parse_transmit_line,
)


NEWLINE = chr(10)


def _trace_page(grid_realigned: bool) -> str:
    lines = ["SIGNATURE 0x4c4f5241"]
    for index in range(128):
        status = 0x53590280
        sequence = 3
        symbol = 10 + index
        sample = 1000 + 1024 * index
        metrics = (2 << 16) | (0x4000 + index)
        debug = (7 << 16) | (index << 9) | (0x100 if grid_realigned else 0) | 128
        lines.append(
            "ENTRY "
            f"{index} 0x{status:08x} 0x{sequence:08x} 0x{symbol:08x} "
            f"0x{sample & 0xffffffff:08x} 0x{sample >> 32:08x} "
            f"0x{metrics:08x} 0x{debug:08x}"
        )
    return "\n".join(lines)


def test_parse_frozen_symbol_trace_page() -> None:
    trace = parse_trace(_trace_page(grid_realigned=False))

    assert trace.capture_sequence == 3
    assert trace.preamble_bin == 7
    assert trace.captured_count == 128
    assert not trace.grid_realigned
    assert trace.entries[5].symbol == 15
    assert trace.entries[5].sample_count == 6120
    assert trace.entries[5].confidence_q15 == 0x4005
    assert trace.entries[5].flags == 2


def test_parse_reports_a_realigned_symbol_grid() -> None:
    """Debug bit 8 says the decisions were taken on the packet grid."""

    trace = parse_trace(_trace_page(grid_realigned=True))

    assert trace.grid_realigned
    assert trace.preamble_bin == 7
    assert trace.captured_count == 128


PROFILE_LINE = (
    "PROFILE freq_mhz=868.100 bw_khz=125.0 sf=7 cr=4/5 sync=0x12 power_dbm=-9 "
    "preamble=12 crc=on iq=normal interval_ms=500 payload=counter length=32 "
    "running=no board_revision=v4.3 fem=kct8103l-bypass revision_probe=0/32 "
    "firmware=0.2.0"
)


def test_parse_profile_reads_the_firmware_show_line() -> None:
    fields = parse_profile(PROFILE_LINE)

    assert fields["freq_mhz"] == "868.100"
    assert fields["sf"] == "7"
    assert fields["cr"] == "4/5"
    assert fields["power_dbm"] == "-9"
    assert fields["running"] == "no"
    assert fields["length"] == "32"


def test_parse_transmit_line_accepts_the_single_send_record() -> None:
    record = parse_transmit_line(
        [
            "OK single packet queued",
            "TX seq=41 len=32 state=0 start_ms=123456 duration_ms=62",
        ]
    )

    assert record == {
        "sequence": 41,
        "payload_length": 32,
        "state": 0,
        "start_ms": 123456,
        "duration_ms": 62,
    }


def test_parse_transmit_line_rejects_a_response_without_a_tx_record() -> None:
    with pytest.raises(RuntimeError):
        parse_transmit_line(["OK transmitter stopped"])


def test_grid_phase_is_removed_only_when_the_receiver_did_not() -> None:
    """Subtracting the preamble bin off a realigned grid would remove it twice."""

    free_running = parse_trace(_trace_page(grid_realigned=False))
    realigned = parse_trace(_trace_page(grid_realigned=True))

    assert grid_phase(free_running) == free_running.preamble_bin == 7
    assert realigned.preamble_bin == 7
    assert grid_phase(realigned) == 0


def _clock_page(
    clocks_per_sample: int = 63,
    minimum: int = 62,
    search_clocks: int = 135443,
    search_count: int = 1,
    overflow: bool = False,
    marker: int = 0x434B,
) -> str:
    status = (marker << 16) | (1 if overflow else 0)
    return (
        f"CLOCK 0x{status:08x} 0x{clocks_per_sample:08x} "
        f"0x{search_clocks:08x} 0x{minimum:08x} 0x{search_count:08x}"
    )


def test_clock_page_reports_the_receiver_clock() -> None:
    text = _trace_page(grid_realigned=False)
    text = text.replace("SIGNATURE 0x4c4f5241", "SIGNATURE 0x4c4f5241\n" + _clock_page())

    trace = parse_trace(text)

    assert trace.clock is not None
    assert trace.clock.clocks_per_sample == 63
    assert trace.clock.clocks_per_sample_min == 62
    assert trace.clock.search_clocks == 135443
    assert not trace.clock.crossing_overflow


def test_clock_summary_accepts_the_fixed_receiver_clock() -> None:
    summary = _clock_summary(
        ClockAccounting(
            clocks_per_sample=63,
            clocks_per_sample_min=62,
            search_clocks=135443,
            search_count=1,
            crossing_overflow=False,
        )
    )

    assert summary is not None
    assert summary["clocks_per_sample_ok"]
    assert summary["sfd_deadline_clocks"] == 145152
    assert summary["search_within_sfd"]


def test_clock_summary_rejects_the_ad9361_derived_clock() -> None:
    """One clock per sample is the defect this page exists to catch.

    The AD9361 divided data clock equals the sample rate, so the whole SFD is
    2304 clocks and the joint search cannot fit in it. Scoring the search
    against the deadline the design *wants* rather than the one it *has* is
    exactly how a fifty-nine-fold overshoot went unnoticed.
    """

    summary = _clock_summary(
        ClockAccounting(
            clocks_per_sample=1,
            clocks_per_sample_min=1,
            search_clocks=55552,
            search_count=1,
            crossing_overflow=False,
        )
    )

    assert summary is not None
    assert not summary["clocks_per_sample_ok"]
    assert summary["sfd_deadline_clocks"] == 2304
    assert not summary["search_within_sfd"]


def test_clock_page_marker_mismatch_is_rejected() -> None:
    text = _trace_page(grid_realigned=False)
    text = text.replace(
        "SIGNATURE 0x4c4f5241",
        "SIGNATURE 0x4c4f5241\n" + _clock_page(marker=0x5359),
    )

    with pytest.raises(ValueError, match="clock page marker"):
        parse_trace(text)


def test_trace_without_a_clock_page_still_parses() -> None:
    """Older bitstreams have no clock page and must stay readable."""

    trace = parse_trace(_trace_page(grid_realigned=False))

    assert trace.clock is None
    assert _clock_summary(trace.clock) is None


def _clock_pages(intervals: list[int]) -> str:
    return NEWLINE.join(
        _clock_page(clocks_per_sample=value, minimum=min(intervals))
        for value in intervals
    )


def test_burst_readings_do_not_look_like_the_ad9361_clock() -> None:
    """util_wfifo hands out eight samples at a time.

    A reading taken inside a burst reports a one-clock gap that is real but is
    not the steady-state ratio, so the page is read several times and the
    largest interval wins. Otherwise a healthy receiver would intermittently
    look exactly like the defect this check exists to catch.
    """

    text = _trace_page(grid_realigned=False).replace(
        "SIGNATURE 0x4c4f5241",
        "SIGNATURE 0x4c4f5241\n" + _clock_pages([1, 63, 1, 62, 63, 63, 1, 63]),
    )

    trace = parse_trace(text)

    assert trace.clock is not None
    assert trace.clock.clocks_per_sample == 63
    summary = _clock_summary(trace.clock)
    assert summary is not None
    assert summary["clocks_per_sample_ok"]


def test_every_reading_one_clock_is_still_caught() -> None:
    """On the AD9361-derived clock there are no spare clocks for a gap."""

    text = _trace_page(grid_realigned=False).replace(
        "SIGNATURE 0x4c4f5241",
        "SIGNATURE 0x4c4f5241\n" + _clock_pages([1] * 8),
    )

    trace = parse_trace(text)

    assert trace.clock is not None
    assert trace.clock.clocks_per_sample == 1
    summary = _clock_summary(trace.clock)
    assert summary is not None
    assert not summary["clocks_per_sample_ok"]
    assert summary["sfd_deadline_clocks"] == 2304
