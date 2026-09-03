import pytest

from tools.read_clg400_symbol_trace import parse_trace
from tools.run_clg400_payload_capture import (
    parse_profile,
    parse_transmit_line,
)


def test_parse_frozen_symbol_trace_page() -> None:
    lines = ["SIGNATURE 0x4c4f5241"]
    for index in range(128):
        status = 0x53590280
        sequence = 3
        symbol = 10 + index
        sample = 1000 + 1024 * index
        metrics = (2 << 16) | (0x4000 + index)
        debug = (7 << 16) | (index << 9) | 128
        lines.append(
            "ENTRY "
            f"{index} 0x{status:08x} 0x{sequence:08x} 0x{symbol:08x} "
            f"0x{sample & 0xffffffff:08x} 0x{sample >> 32:08x} "
            f"0x{metrics:08x} 0x{debug:08x}"
        )

    trace = parse_trace("\n".join(lines))

    assert trace.capture_sequence == 3
    assert trace.preamble_bin == 7
    assert trace.captured_count == 128
    assert trace.entries[5].symbol == 15
    assert trace.entries[5].sample_count == 6120
    assert trace.entries[5].confidence_q15 == 0x4005
    assert trace.entries[5].flags == 2


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
