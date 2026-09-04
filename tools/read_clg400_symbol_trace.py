#!/usr/bin/env python3
"""Arm, read, and hard-decode the frozen CLG400 LoRa symbol trace."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from dataclasses import asdict, dataclass
from pathlib import Path

from zynq_lora_phy import decode_lora_symbol_trace


CONTROL = "0x79040404"
STATUS = "0x79040408"
SEQUENCE = "0x79040448"
SYMBOL = "0x79040488"
SAMPLE_LO = "0x790404c8"
SAMPLE_HI = "0x79040508"
METRICS = "0x79040548"
DEBUG = "0x79040588"
SIGNATURE = "0x790405c8"


@dataclass(frozen=True)
class TraceEntry:
    index: int
    symbol: int
    sample_count: int
    confidence_q15: int
    flags: int


@dataclass(frozen=True)
class SymbolTrace:
    capture_sequence: int
    preamble_bin: int
    captured_count: int
    grid_realigned: bool
    entries: tuple[TraceEntry, ...]


def _ssh_args(args: argparse.Namespace) -> list[str]:
    command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={args.connect_timeout}",
    ]
    if args.identity:
        command.extend(["-i", str(args.identity)])
    command.extend([f"{args.user}@{args.host}", "sh", "-s"])
    return command


def _run_remote(args: argparse.Namespace, script: str) -> str:
    if args.password_env:
        password = os.environ.get(args.password_env)
        if password is None:
            raise ValueError(
                f"SSH password environment variable {args.password_env!r} is not set"
            )
        try:
            import paramiko
        except ImportError as error:
            raise RuntimeError(
                "password SSH requires the hardware extra (paramiko)"
            ) from error

        client = paramiko.SSHClient()
        if args.known_hosts:
            client.load_host_keys(str(args.known_hosts))
        else:
            client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        try:
            try:
                client.connect(
                    args.host,
                    username=args.user,
                    password=password,
                    timeout=args.connect_timeout,
                    banner_timeout=args.connect_timeout,
                    auth_timeout=args.connect_timeout,
                    allow_agent=False,
                    look_for_keys=False,
                )
                stdin, stdout, stderr = client.exec_command(
                    "sh -s", timeout=args.command_timeout
                )
                stdin.write(script)
                stdin.flush()
                stdin.channel.shutdown_write()
                output = stdout.read().decode("utf-8", errors="replace")
                detail = stderr.read().decode("utf-8", errors="replace").strip()
                status = stdout.channel.recv_exit_status()
            except paramiko.SSHException as error:
                raise RuntimeError(f"remote CLG400 SSH failed: {error}") from error
        finally:
            client.close()
        if status:
            raise RuntimeError(f"remote CLG400 command failed: {detail or output.strip()}")
        return output

    completed = subprocess.run(
        _ssh_args(args),
        input=script,
        text=True,
        capture_output=True,
        check=False,
        timeout=args.command_timeout,
    )
    if completed.returncode:
        detail = completed.stderr.strip() or completed.stdout.strip()
        raise RuntimeError(f"remote CLG400 command failed: {detail}")
    return completed.stdout


def arm_trace(args: argparse.Namespace) -> None:
    # This only resets/re-arms the receive stream. It does not touch QSPI,
    # FPGA manager, AD9361 TX controls, or any RF transmitter.
    script = f"""set -eu
orig=$(devmem {CONTROL} 32)
reset=$((orig | 2))
run=$((orig & 0xfffffffd))
devmem {CONTROL} 32 "$reset" >/dev/null
sleep 1
devmem {CONTROL} 32 "$run" >/dev/null
printf 'armed control=0x%08x\\n' "$run"
"""
    output = _run_remote(args, script).strip()
    print(output)


def _read_script(depth: int) -> str:
    return f"""set -eu
orig=$(devmem {CONTROL} 32)
restore() {{ devmem {CONTROL} 32 "$orig" >/dev/null; }}
trap restore EXIT HUP INT TERM
sig=$(devmem {SIGNATURE} 32)
printf 'SIGNATURE %s\\n' "$sig"
i=0
while [ "$i" -lt {depth} ]; do
  selector=$(((orig & 0x80feffff) | 0x00010000 | (i << 24)))
  devmem {CONTROL} 32 "$selector" >/dev/null
  status=$(devmem {STATUS} 32)
  sequence=$(devmem {SEQUENCE} 32)
  symbol=$(devmem {SYMBOL} 32)
  sample_lo=$(devmem {SAMPLE_LO} 32)
  sample_hi=$(devmem {SAMPLE_HI} 32)
  metrics=$(devmem {METRICS} 32)
  debug=$(devmem {DEBUG} 32)
  printf 'ENTRY %u %s %s %s %s %s %s %s\\n' \
    "$i" "$status" "$sequence" "$symbol" "$sample_lo" "$sample_hi" \
    "$metrics" "$debug"
  i=$((i + 1))
done
"""


def parse_trace(text: str) -> SymbolTrace:
    signature: int | None = None
    rows: list[tuple[int, ...]] = []
    for line in text.splitlines():
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "SIGNATURE" and len(fields) == 2:
            signature = int(fields[1], 0)
        elif fields[0] == "ENTRY" and len(fields) == 9:
            rows.append(tuple([int(fields[1], 10)] + [int(value, 0) for value in fields[2:]]))
    if signature != 0x4C4F5241:
        raise ValueError(f"unexpected bridge signature: {signature!r}")
    if not rows:
        raise ValueError("remote output contained no trace entries")

    status_values = {row[1] for row in rows}
    sequence_values = {row[2] for row in rows}
    debug_values = {row[7] & 0xFFFF01FF for row in rows}
    if len(status_values) != 1 or len(sequence_values) != 1 or len(debug_values) != 1:
        raise ValueError("trace status changed while the frozen buffer was read")

    status = rows[0][1]
    if status >> 16 != 0x5359:
        raise ValueError(f"symbol-trace page is unavailable: status=0x{status:08x}")
    captured_count = status & 0xFF
    capture_active = bool(status & 0x100)
    capture_complete = bool(status & 0x200)
    if capture_active or not capture_complete:
        raise ValueError(
            f"symbol trace is not complete: active={capture_active}, "
            f"captured={captured_count}"
        )
    if captured_count > len(rows):
        raise ValueError("captured count exceeds returned trace depth")

    preamble_bin = rows[0][7] >> 16
    grid_realigned = bool(rows[0][7] & 0x100)
    entries = tuple(
        TraceEntry(
            index=row[0],
            symbol=row[3],
            sample_count=row[4] | (row[5] << 32),
            confidence_q15=row[6] & 0xFFFF,
            flags=(row[6] >> 16) & 0xFF,
        )
        for row in rows[:captured_count]
    )
    return SymbolTrace(
        rows[0][2], preamble_bin, captured_count, grid_realigned, entries
    )


def read_trace(args: argparse.Namespace) -> SymbolTrace:
    return parse_trace(_run_remote(args, _read_script(args.depth)))


def _payload_summary(payload: bytes) -> dict[str, object]:
    printable = "".join(chr(value) if 32 <= value < 127 else "." for value in payload)
    summary: dict[str, object] = {"hex": payload.hex(), "ascii": printable}
    if len(payload) >= 12 and payload[:4] == b"ZLP1":
        summary.update(
            {
                "format": "ZLP1",
                "sequence": int.from_bytes(payload[4:8], "little"),
                "start_ms": int.from_bytes(payload[8:12], "little"),
            }
        )
    return summary


def grid_phase(trace: SymbolTrace) -> int:
    """The bin offset software still has to remove from the raw decisions.

    The preamble bin measures where the symbol grid sat when the packet
    arrived. If the receiver then realigned its grid to that packet, it has
    already removed the offset -- including the integer part of any carrier
    offset, which an upchirp-only measurement cannot tell apart from timing --
    and the raw decisions are the transmitted symbols. Subtracting the measured
    bin again would remove it twice.
    """

    return 0 if trace.grid_realigned else trace.preamble_bin


def build_report(trace: SymbolTrace) -> dict[str, object]:
    candidate = decode_lora_symbol_trace(
        [entry.symbol for entry in trace.entries], grid_phase(trace)
    )
    result = candidate.result
    header = asdict(result.header) if result.header is not None else None
    return {
        "schema": "zynq-lora-clg400-symbol-trace-v1",
        "capture_sequence": trace.capture_sequence,
        "preamble_bin": trace.preamble_bin,
        "grid_phase_removed": grid_phase(trace),
        "captured_count": trace.captured_count,
        "grid_realigned": trace.grid_realigned,
        "decode": {
            "success": result.success,
            "header_valid": result.header_valid,
            "crc_valid": result.crc_valid,
            "failure_reason": result.failure_reason,
            "symbol_offset": candidate.symbol_offset,
            "bin_adjustment": candidate.bin_adjustment,
            "consumed_symbol_count": result.consumed_symbol_count,
            "header": header,
            "payload": _payload_summary(result.payload),
        },
        "entries": [asdict(entry) for entry in trace.entries],
    }


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
    parser.add_argument(
        "--known-hosts",
        type=Path,
        help="pinned known_hosts file for password SSH; system known_hosts otherwise",
    )
    parser.add_argument("--depth", type=int, default=128, choices=[128])
    parser.add_argument("--connect-timeout", type=int, default=5)
    parser.add_argument("--command-timeout", type=int, default=60)
    parser.add_argument(
        "--arm",
        action="store_true",
        help="re-arm the RX-only trace before reading; send the packet separately",
    )
    parser.add_argument("--output", type=Path, help="write the full trace/report JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.arm:
            arm_trace(args)
            print("Trace armed. Send one packet, wait 0.2 s, then rerun without --arm.")
            return 0
        report = build_report(read_trace(args))
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    rendered = json.dumps(report, indent=2, ensure_ascii=False)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered + "\n", encoding="utf-8")
    decode = report["decode"]
    payload = decode["payload"]
    print(
        f"capture={report['capture_sequence']} symbols={report['captured_count']} "
        f"preamble_bin={report['preamble_bin']} "
        f"grid_realigned={report['grid_realigned']} "
        f"offset={decode['symbol_offset']} "
        f"bin_adjust={decode['bin_adjustment']}"
    )
    print(
        f"header_valid={decode['header_valid']} crc_valid={decode['crc_valid']} "
        f"payload={payload['hex']}"
    )
    if payload.get("format") == "ZLP1":
        print(f"ZLP1 sequence={payload['sequence']} start_ms={payload['start_ms']}")
    if args.output:
        print(f"saved {args.output}")
    return 0 if decode["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
