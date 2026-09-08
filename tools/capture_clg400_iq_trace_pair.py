#!/usr/bin/env python3
"""Capture one Heltec packet as a simultaneous RX1 IQ recording and PL trace.

The stage-by-stage differential needs both halves of the same packet: the raw
samples the AD9361 delivered and the decisions the programmable logic froze
from them. Recording them separately is not good enough — the comparison only
means something if both describe the same transmission.

Per attempt: arm the PL trace, start the DMA recording so it brackets the
transmission, issue exactly one ``send``, read the frozen trace, download the
IQ. The transmitter is stopped before and immediately after the send and
``start`` is never issued, so no periodic transmission can be left running.

Everything on the receiver is read-only apart from the receive-stream reset
that re-arms the trace. QSPI, the boot loader, the FPGA manager and every RF
transmit enable are untouched.

The recording is written to the board's tmpfs and streamed back over the same
SSH connection, so nothing is left on the board and the multi-megabyte capture
never enters Git — ``experiments/runs/`` is ignored.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.read_clg400_symbol_trace import (  # noqa: E402
    CONTROL,
    _run_remote,
    build_report,
    read_trace,
)
from tools.run_clg400_payload_capture import (  # noqa: E402
    EXPECTED_PROFILE,
    transmit_once,
)


# 1.5 s at 1 MS/s. The packet is ~83 ms, so this brackets it with room for the
# arming delay either side without making the transfer slow.
DEFAULT_IQ_SAMPLES = 1_500_000
REMOTE_IQ = "/tmp/lora_rx1.bin"


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def arm_receive_stream(args: argparse.Namespace) -> str:
    """Re-arm the frozen trace by pulsing the receive-stream reset."""

    script = f"""set -eu
orig=$(devmem {CONTROL} 32)
reset=$((orig | 2))
run=$((orig & 0xfffffffd))
devmem {CONTROL} 32 "$reset" >/dev/null
sleep 1
devmem {CONTROL} 32 "$run" >/dev/null
printf 'armed control=0x%08x\\n' "$run"
"""
    return _run_remote(args, script).strip()


def iio_capture_command(samples: int, remote_path: str) -> str:
    """Build the detached DMA recording command.

    ``iio_readdev`` writes one interleaved little-endian int16 pair per sample
    with both channels selected, which is exactly the format the analysis
    tools expect. It is detached so the transmission can happen while the
    buffer fills; the exit status lands in a sentinel file.
    """

    if samples <= 0:
        raise ValueError("samples must be positive")
    return (
        f"rm -f {remote_path} {remote_path}.done; "
        f"( iio_readdev -u local: -b 32768 -s {samples} cf-ad9361-lpc "
        f"voltage0 voltage1 > {remote_path} 2>/tmp/lora_rx1.err; "
        f"echo $? > {remote_path}.done ) >/dev/null 2>&1 &"
    )


def wait_for_capture(
    args: argparse.Namespace, remote_path: str, timeout_s: float
) -> tuple[int, int]:
    """Block until the detached recording writes its sentinel."""

    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        fields = _run_remote(
            args,
            f"if [ -f {remote_path}.done ]; then cat {remote_path}.done; "
            f"else echo pending; fi; "
            f"stat -c %s {remote_path} 2>/dev/null || echo 0",
        ).split()
        if fields and fields[0] != "pending":
            return int(fields[0]), int(fields[1])
        time.sleep(0.5)
    raise TimeoutError("the DMA recording did not finish before the deadline")


def fetch_binary(args: argparse.Namespace, remote_path: str, local: Path) -> int:
    """Stream a remote binary back; the board image has no SFTP subsystem."""

    if args.password_env:
        import paramiko

        password = os.environ.get(args.password_env)
        if password is None:
            raise ValueError(
                f"SSH password environment variable {args.password_env!r} is not set"
            )
        client = paramiko.SSHClient()
        if args.known_hosts:
            client.load_host_keys(str(args.known_hosts))
        else:
            client.load_system_host_keys()
        client.set_missing_host_key_policy(paramiko.RejectPolicy())
        try:
            client.connect(
                args.host,
                username=args.user,
                password=password,
                timeout=args.connect_timeout,
                allow_agent=False,
                look_for_keys=False,
            )
            stdin, stdout, stderr = client.exec_command(
                f"cat {remote_path}", timeout=args.command_timeout
            )
            stdin.channel.shutdown_write()
            written = 0
            with local.open("wb") as handle:
                while True:
                    chunk = stdout.channel.recv(65536)
                    if not chunk:
                        if stdout.channel.exit_status_ready():
                            break
                        continue
                    handle.write(chunk)
                    written += len(chunk)
            if stdout.channel.recv_exit_status():
                raise RuntimeError(stderr.read().decode(errors="replace").strip())
        finally:
            client.close()
        return written

    command = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={args.connect_timeout}",
    ]
    if args.known_hosts:
        command.extend(["-o", f"UserKnownHostsFile={args.known_hosts}"])
    if args.identity:
        command.extend(["-i", str(args.identity)])
    command.extend([f"{args.user}@{args.host}", "cat", remote_path])
    completed = subprocess.run(command, capture_output=True, check=False)
    if completed.returncode:
        raise RuntimeError(
            f"reading {remote_path} failed: {completed.stderr.decode(errors='replace').strip()}"
        )
    local.write_bytes(completed.stdout)
    return len(completed.stdout)


def capture_once(args: argparse.Namespace) -> dict[str, object]:
    stamp = utc_stamp()
    args.run_dir.mkdir(parents=True, exist_ok=True)
    serial_log = args.run_dir / f"heltec-{stamp}.log"
    local_iq = args.run_dir / f"rx1-iq-{stamp}.bin"

    print(f"[{stamp}] {arm_receive_stream(args)}")
    _run_remote(args, iio_capture_command(args.iq_samples, REMOTE_IQ))
    time.sleep(args.settle_s)

    identity, record = transmit_once(
        args.port, args.baud, serial_log, EXPECTED_PROFILE
    )

    status, remote_size = wait_for_capture(args, REMOTE_IQ, args.capture_timeout_s)
    if status != 0:
        raise RuntimeError(f"iio_readdev exited {status}")
    expected_bytes = args.iq_samples * 4
    if remote_size != expected_bytes:
        raise RuntimeError(
            f"recording is {remote_size} bytes, expected {expected_bytes}"
        )

    time.sleep(args.settle_s)
    report = build_report(read_trace(args))
    downloaded = fetch_binary(args, REMOTE_IQ, local_iq)
    _run_remote(args, f"rm -f {REMOTE_IQ} {REMOTE_IQ}.done")

    report["serial"] = {
        "port": args.port,
        "log": serial_log.name,
        "transmitted_utc": stamp,
        "iq_capture": local_iq.name,
        "version": identity["version"],
        "profile": identity["profile"],
        "tx_sequence": record["sequence"],
        "tx_payload_length": record["payload_length"],
        "tx_state": record["state"],
        "tx_start_ms": record["start_ms"],
        "tx_duration_ms": record["duration_ms"],
    }
    report["iq_bytes"] = downloaded
    report["iq_samples"] = downloaded // 4

    trace_path = args.run_dir / f"clg400-trace-{stamp}.json"
    trace_path.write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    decode = report["decode"]
    print(
        f"[{stamp}] seq={record['sequence']} "
        f"capture_sequence={report['capture_sequence']} "
        f"count={report['captured_count']} realigned={report['grid_realigned']} "
        f"preamble_bin={report['preamble_bin']} "
        f"header={decode['header_valid']} crc={decode['crc_valid']} "
        f"iq={downloaded} bytes"
    )
    return report


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="192.168.40.1")
    parser.add_argument("--user", default="root")
    parser.add_argument("--identity", type=Path)
    parser.add_argument(
        "--password-env",
        help="read the SSH password from environment variable NAME via paramiko",
    )
    parser.add_argument("--known-hosts", type=Path)
    parser.add_argument("--connect-timeout", type=int, default=5)
    parser.add_argument("--command-timeout", type=int, default=600)
    parser.add_argument("--depth", type=int, default=128)
    parser.add_argument("--port", default="COM10")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--run-dir", type=Path, required=True)
    parser.add_argument("--attempts", type=int, default=1)
    parser.add_argument("--iq-samples", type=int, default=DEFAULT_IQ_SAMPLES)
    parser.add_argument("--settle-s", type=float, default=0.25)
    parser.add_argument("--gap-s", type=float, default=1.5)
    parser.add_argument("--capture-timeout-s", type=float, default=60)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    completed = 0
    for index in range(args.attempts):
        try:
            capture_once(args)
            completed += 1
        except Exception as error:  # noqa: BLE001 - one attempt must not end the run
            print(
                f"ATTEMPT {index + 1} FAILED: {type(error).__name__}: {error}",
                file=sys.stderr,
            )
        if index + 1 < args.attempts:
            time.sleep(args.gap_s)
    print(f"attempts={args.attempts} captured={completed}")
    return 0 if completed else 1


if __name__ == "__main__":
    raise SystemExit(main())
