#!/usr/bin/env python3
"""Run one Heltec transmission against the frozen CLG400 symbol trace.

The over-the-air payload gate needs a single attempt to carry its own evidence:
the transmitter profile, the sequence number the transmitter reported, and the
trace that was armed before that transmission and read after it. Doing it by
hand invites the two failure modes this script removes -- a periodic
transmission left running, and a trace that was already frozen by an earlier
packet.

The transmitter is stopped before and immediately after the single ``send``;
``start`` is never issued. Everything on the receiver side is read-only apart
from the receive-stream reset that re-arms the trace.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.read_clg400_symbol_trace import (  # noqa: E402
    arm_trace,
    build_report,
    read_trace,
)
from tools.run_phy_experiment import SerialTransmitter  # noqa: E402


EXPECTED_PROFILE = {
    "freq_mhz": "868.100",
    "bw_khz": "125.0",
    "sf": "7",
    "cr": "4/5",
    "sync": "0x12",
    "power_dbm": "-9",
    "preamble": "12",
    "crc": "on",
    "iq": "normal",
    "payload": "counter",
    "length": "32",
    "running": "no",
}

TX_LINE = re.compile(
    r"TX seq=(\d+) len=(\d+) state=(-?\d+) start_ms=(\d+) duration_ms=(\d+)"
)


def parse_profile(line: str) -> dict[str, str]:
    """Split a firmware ``PROFILE key=value ...`` line into a mapping."""

    fields: dict[str, str] = {}
    for token in line.split()[1:]:
        key, separator, value = token.partition("=")
        if separator:
            fields[key] = value
    return fields


def parse_transmit_line(lines: list[str]) -> dict[str, int]:
    """Extract the accepted ``TX seq=...`` record from one send response."""

    for line in lines:
        match = TX_LINE.match(line)
        if match:
            return {
                "sequence": int(match.group(1)),
                "payload_length": int(match.group(2)),
                "state": int(match.group(3)),
                "start_ms": int(match.group(4)),
                "duration_ms": int(match.group(5)),
            }
    raise RuntimeError(f"no 'TX seq=...' response line in {lines!r}")


def transmit_once(
    port: str, baud: int, log_path: Path, expected: dict[str, str]
) -> tuple[dict[str, object], dict[str, int]]:
    transmitter = SerialTransmitter(port, baud, log_path)
    try:
        transmitter.command("stop", quiet_s=0.4)
        version_lines = transmitter.command("version", quiet_s=0.4)
        version = next(
            (line for line in version_lines if line.startswith("zynq-lora")), ""
        )

        profile_line = _read_profile(transmitter)
        fields = parse_profile(profile_line)
        # A power cycle drops the transmitter back to its 0 dBm default; the
        # documented link profile is -9 dBm and the evidence has to match it.
        if fields.get("power_dbm") != expected["power_dbm"]:
            transmitter.command(f"set power {expected['power_dbm']}", quiet_s=0.4)
            profile_line = _read_profile(transmitter)
            fields = parse_profile(profile_line)

        mismatch = {
            key: {"expected": value, "actual": fields.get(key)}
            for key, value in expected.items()
            if fields.get(key) != value
        }
        if mismatch:
            raise RuntimeError(f"transmitter profile mismatch: {mismatch}")

        send_lines = transmitter.command(
            "send", quiet_s=0.4, required_prefix="TX seq=", response_timeout_s=15
        )
        transmitter.command("stop", quiet_s=0.4)
    finally:
        transmitter.close()

    record = parse_transmit_line(send_lines)
    if record["state"] != 0:
        raise RuntimeError(f"transmitter reported state={record['state']}")
    return {"version": version, "profile": profile_line}, record


def _read_profile(transmitter: SerialTransmitter) -> str:
    lines = transmitter.command("show", quiet_s=0.4)
    profile = next((line for line in lines if line.startswith("PROFILE")), "")
    if not profile:
        raise RuntimeError("transmitter did not report a PROFILE line")
    return profile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.40.1")
    parser.add_argument("--user", default="root")
    parser.add_argument("--identity", type=Path)
    parser.add_argument(
        "--password-env",
        metavar="NAME",
        help="read the SSH password from environment variable NAME via paramiko",
    )
    parser.add_argument("--known-hosts", type=Path)
    parser.add_argument("--connect-timeout", type=int, default=5)
    parser.add_argument("--command-timeout", type=int, default=180)
    parser.add_argument("--port", default="COM10")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument(
        "--run-dir",
        type=Path,
        required=True,
        help="ignored directory for the serial log and the saved trace JSON",
    )
    parser.add_argument(
        "--settle-s",
        type=float,
        default=0.5,
        help="delay between the transmission and the trace read",
    )
    parser.add_argument(
        "--no-arm",
        action="store_true",
        help="read an already frozen trace instead of arming a fresh capture",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    remote = argparse.Namespace(
        host=args.host,
        user=args.user,
        identity=args.identity,
        password_env=args.password_env,
        known_hosts=args.known_hosts,
        depth=128,
        connect_timeout=args.connect_timeout,
        command_timeout=args.command_timeout,
    )

    args.run_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    serial_log = args.run_dir / f"heltec-{stamp}.log"
    trace_path = args.run_dir / f"clg400-trace-{stamp}.json"

    if not args.no_arm:
        arm_trace(remote)

    identity, record = transmit_once(
        args.port, args.baud, serial_log, EXPECTED_PROFILE
    )
    time.sleep(args.settle_s)

    report = build_report(read_trace(remote))
    report["serial"] = {
        "port": args.port,
        "log": serial_log.name,
        "transmitted_utc": stamp,
        **identity,
        **{f"tx_{key}": value for key, value in record.items()},
    }
    trace_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    decode = report["decode"]
    payload = decode["payload"]
    print(f"saved {trace_path}")
    print(
        f"tx_sequence={record['sequence']} capture={report['capture_sequence']} "
        f"captured={report['captured_count']} "
        f"preamble_bin={report['preamble_bin']} "
        f"grid_realigned={report['grid_realigned']} "
        f"offset={decode['symbol_offset']} "
        f"bin_adjustment={decode['bin_adjustment']}"
    )
    print(
        f"header_valid={decode['header_valid']} crc_valid={decode['crc_valid']} "
        f"header={decode['header']} reason={decode['failure_reason']!r}"
    )
    print(f"payload_hex={payload['hex']}")
    print(f"payload_ascii={payload['ascii']}")
    if payload.get("format") == "ZLP1":
        print(f"ZLP1 sequence={payload['sequence']} start_ms={payload['start_ms']}")
        if decode["crc_valid"] and payload["sequence"] == record["sequence"]:
            print("ACCEPT: payload CRC valid and ZLP1 sequence matches the transmitter")
            return 0
    print("REJECT: this attempt does not meet the payload acceptance criteria")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
