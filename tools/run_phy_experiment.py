"""Run a synchronized LoRa transmit, IQ capture, and MATLAB analysis session."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_config(path: Path) -> dict[str, Any]:
    config = json.loads(path.read_text(encoding="utf-8"))
    validate_config(config)
    return config


def lora_airtime_seconds(transmitter: dict[str, Any]) -> float:
    sf = transmitter["spreading_factor"]
    bandwidth = transmitter["bandwidth_hz"]
    payload_length = transmitter.get("payload_length", 32)
    if transmitter.get("payload", "counter") != "counter":
        encoded = str(transmitter["payload"]).replace("0x", "").replace(" ", "")
        payload_length = len(encoded) // 2
    symbol_time = 2**sf / bandwidth
    low_data_rate_optimization = 1 if symbol_time >= 0.016 else 0
    crc = 1 if transmitter["crc_enabled"] else 0
    numerator = 8*payload_length - 4*sf + 28 + 16*crc
    denominator = 4*(sf - 2*low_data_rate_optimization)
    coding_rate_index = transmitter["coding_rate_denominator"] - 4
    payload_symbols = 8 + max(
        math.ceil(numerator/denominator)*(coding_rate_index + 4), 0
    )
    preamble_symbols = transmitter["preamble_symbols"] + 4.25
    return (preamble_symbols + payload_symbols)*symbol_time


def validate_config(config: dict[str, Any]) -> None:
    if config.get("schema") != "zynq-lora-one-machine-v1":
        raise ValueError("Unsupported or missing configuration schema")
    transmitter = config["transmitter"]
    receiver = config["receiver"]
    analysis = config.get("analysis", {})
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", config.get("run_name", "")):
        raise ValueError("run_name may contain only letters, digits, dot, underscore, and dash")
    if transmitter["packet_count"] < 1:
        raise ValueError("transmitter.packet_count must be positive")
    if transmitter["packet_interval_ms"] < 20:
        raise ValueError("transmitter.packet_interval_ms must be at least 20")
    if transmitter["spreading_factor"] not in range(5, 13):
        raise ValueError("transmitter.spreading_factor must be from 5 to 12")
    if transmitter["coding_rate_denominator"] not in range(5, 9):
        raise ValueError("transmitter.coding_rate_denominator must be 5..8")
    if receiver["type"] not in {"pluto", "rtl_sdr"}:
        raise ValueError("receiver.type must be pluto or rtl_sdr")
    if receiver["sample_rate_hz"] <= transmitter["bandwidth_hz"]:
        raise ValueError("receiver sample rate must exceed LoRa bandwidth")
    if receiver["duration_s"] <= 0:
        raise ValueError("receiver.duration_s must be positive")
    send_window = (
        (transmitter["packet_count"] - 1)
        * transmitter["packet_interval_ms"]
        / 1000
    )
    transmit_time = transmitter["packet_count"]*lora_airtime_seconds(transmitter)
    host_command_margin = 0.15*transmitter["packet_count"] + 0.5
    if receiver["duration_s"] <= send_window + transmit_time + host_command_margin:
        raise ValueError("receiver duration is too short for the packet sequence")
    if analysis.get("enabled", True) and not analysis.get("matlab_command", "matlab"):
        raise ValueError("analysis.matlab_command must not be empty")


def validate_execution_config(config: dict[str, Any]) -> None:
    if config.get("bench", {}).get("antenna_or_cable_path") == "EDIT BEFORE RUN":
        raise ValueError("Describe bench.antenna_or_cable_path before --execute")


def transmitter_commands(config: dict[str, Any]) -> list[str]:
    tx = config["transmitter"]
    commands = [
        "stop",
        f"set freq {tx['frequency_hz']/1e6:.6f}",
        f"set bw {tx['bandwidth_hz']/1e3:g}",
        f"set sf {tx['spreading_factor']}",
        f"set cr {tx['coding_rate_denominator']}",
        f"set power {tx['power_dbm']}",
        f"set preamble {tx['preamble_symbols']}",
        f"set sync {tx['sync_word']}",
        f"set crc {'on' if tx['crc_enabled'] else 'off'}",
        f"set iq {'inverted' if tx['iq_inverted'] else 'normal'}",
    ]
    payload = tx.get("payload", "counter")
    if payload == "counter":
        commands.extend([f"set length {tx['payload_length']}", "payload counter"])
    else:
        commands.append(f"payload hex {payload}")
    commands.append("show")
    return commands


def receiver_command(
    config: dict[str, Any], capture_directory: Path, ready_file: Path
) -> list[str]:
    receiver = config["receiver"]
    tx = config["transmitter"]
    samples = math.ceil(receiver["duration_s"] * receiver["sample_rate_hz"])
    if receiver["type"] == "pluto":
        return [
            sys.executable,
            str(REPOSITORY_ROOT / "tools" / "capture_pluto.py"),
            "--uri",
            receiver.get("uri", "ip:192.168.2.1"),
            "--signal-frequency",
            str(tx["frequency_hz"]),
            "--center-frequency",
            str(receiver["center_frequency_hz"]),
            "--sample-rate",
            str(receiver["sample_rate_hz"]),
            "--rf-bandwidth",
            str(receiver["rf_bandwidth_hz"]),
            "--gain",
            str(receiver["gain_db"]),
            "--samples",
            str(samples),
            "--count",
            "1",
            "--warmup",
            str(receiver.get("warmup_buffers", 2)),
            "--timeout-ms",
            str(receiver.get("iio_timeout_ms", 30_000)),
            "--output",
            str(capture_directory),
            "--ready-file",
            str(ready_file),
        ]
    output = capture_directory / "rtl-capture.cu8"
    return [
        receiver.get("executable", "rtl_sdr"),
        "-d",
        str(receiver.get("device_index", 0)),
        "-f",
        str(receiver["center_frequency_hz"]),
        "-s",
        str(receiver["sample_rate_hz"]),
        "-g",
        str(receiver["gain_db"]),
        "-p",
        str(receiver.get("frequency_correction_ppm", 0)),
        "-n",
        str(samples),
        str(output),
    ]


def matlab_expression(
    config: dict[str, Any], capture_path: Path, analysis_directory: Path
) -> str:
    receiver = config["receiver"]
    tx = config["transmitter"]
    capture_format = "cf32" if capture_path.suffix.lower() == ".cf32" else "cu8"

    def quote(path: Path) -> str:
        return str(path.resolve()).replace("\\", "/").replace("'", "''")

    return (
        f"cd('{quote(REPOSITORY_ROOT / 'model' / 'matlab')}');"
        f"analyze_iq_capture('{quote(capture_path)}','{capture_format}',"
        f"{receiver['sample_rate_hz']},{receiver['center_frequency_hz']},"
        f"{tx['frequency_hz']},'{quote(analysis_directory)}');"
    )


def wait_for_file(path: Path, process: subprocess.Popen[str], timeout_s: float) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        if path.is_file():
            return
        if process.poll() is not None:
            stdout, stderr = process.communicate()
            raise RuntimeError(
                f"Receiver stopped before it was armed\nstdout:\n{stdout}\nstderr:\n{stderr}"
            )
        time.sleep(0.05)
    raise TimeoutError(f"Receiver did not become ready within {timeout_s:g} s")


class SerialTransmitter:
    def __init__(self, port: str, baud: int, log_path: Path):
        try:
            import serial
        except ImportError as error:
            raise RuntimeError("Install pyserial: python -m pip install pyserial") from error
        # Opening ESP32-S3 USB CDC with DTR/RTS asserted can reset the board.
        # Configure both lines before opening so back-to-back sweep cases keep
        # the already-running reference firmware alive.
        self._serial = serial.Serial()
        self._serial.port = port
        self._serial.baudrate = baud
        self._serial.timeout = 0.1
        self._serial.write_timeout = 1
        self._serial.dtr = False
        self._serial.rts = False
        self._serial.open()
        self._log = log_path.open("w", encoding="utf-8")
        time.sleep(0.5)
        self.drain(0.5)

    def close(self) -> None:
        self.drain(0.2)
        self._serial.close()
        self._log.close()

    def drain(self, quiet_s: float) -> list[str]:
        lines: list[str] = []
        deadline = time.monotonic() + quiet_s
        while time.monotonic() < deadline:
            raw = self._serial.readline()
            if not raw:
                continue
            line = raw.decode("utf-8", errors="replace").strip()
            if line:
                record = f"{utc_now()} RX {line}"
                self._log.write(record + "\n")
                self._log.flush()
                print(record)
                lines.append(line)
                deadline = time.monotonic() + quiet_s
        return lines

    def command(
        self,
        command: str,
        quiet_s: float = 0.3,
        required_prefix: str | None = None,
        response_timeout_s: float = 10,
    ) -> list[str]:
        record = f"{utc_now()} TX {command}"
        self._log.write(record + "\n")
        self._log.flush()
        print(record)
        self._serial.write((command + "\n").encode("ascii"))
        self._serial.flush()
        lines: list[str] = []
        if required_prefix is not None:
            deadline = time.monotonic() + response_timeout_s
            while time.monotonic() < deadline:
                raw = self._serial.readline()
                if not raw:
                    continue
                line = raw.decode("utf-8", errors="replace").strip()
                if not line:
                    continue
                logged = f"{utc_now()} RX {line}"
                self._log.write(logged + "\n")
                self._log.flush()
                print(logged)
                lines.append(line)
                if line.startswith(required_prefix):
                    break
            else:
                raise TimeoutError(
                    f"No '{required_prefix}' response to '{command}' within "
                    f"{response_timeout_s:g} s"
                )
            lines.extend(self.drain(quiet_s))
        else:
            lines = self.drain(quiet_s)
            if not lines:
                raise TimeoutError(f"No serial response to '{command}'")
        errors = [line for line in lines if line.startswith("ERR") or "FATAL" in line]
        if errors:
            raise RuntimeError(f"Transmitter rejected '{command}': {errors[-1]}")
        return lines


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, default=REPOSITORY_ROOT / "artifacts" / "phy-runs")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--execute",
        action="store_true",
        help="Explicitly authorize serial control, RF transmission, and recording",
    )
    parser.add_argument("--skip-analysis", action="store_true")
    return parser.parse_args()


def print_plan(config: dict[str, Any], receiver: list[str]) -> None:
    print("Transmitter setup:")
    for command in transmitter_commands(config):
        print(f"  {command}")
    print(f"  send x {config['transmitter']['packet_count']}")
    print("Receiver:")
    print("  " + subprocess.list2cmdline(receiver))
    print("Analysis:")
    print("  MATLAB batch report" if config.get("analysis", {}).get("enabled", True) else "  disabled")


def run() -> Path:
    args = parse_args()
    if args.dry_run == args.execute:
        raise ValueError("Choose exactly one of --dry-run or --execute")
    config = load_config(args.config)
    if args.execute:
        validate_execution_config(config)
    started = datetime.now(timezone.utc)
    run_name = config.get("run_name", "lora-phy").replace(" ", "-")
    run_id = f"{started.strftime('%Y%m%dT%H%M%SZ')}-{run_name}"
    run_directory = args.output_root.resolve() / run_id
    capture_directory = run_directory / "capture"
    analysis_directory = run_directory / "analysis"
    ready_file = run_directory / ".receiver-ready"
    command = receiver_command(config, capture_directory, ready_file)
    print_plan(config, command)
    if args.dry_run:
        return run_directory

    capture_directory.mkdir(parents=True)
    analysis_directory.mkdir()
    shutil.copy2(args.config, run_directory / "experiment-config.json")
    metadata: dict[str, Any] = {
        "schema": "zynq-lora-one-machine-result-v1",
        "run_id": run_id,
        "started_utc": started.isoformat(),
        "repository_commit": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=REPOSITORY_ROOT, text=True
        ).strip(),
        "repository_dirty": bool(
            subprocess.check_output(
                ["git", "status", "--porcelain"], cwd=REPOSITORY_ROOT, text=True
            ).strip()
        ),
        "config": config,
        "receiver_command": command,
        "transmissions": [],
        "captures": [],
        "analysis": [],
        "status": "running",
    }
    metadata_path = run_directory / "run.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")

    transmitter: SerialTransmitter | None = None
    receiver_process: subprocess.Popen[str] | None = None
    try:
        transmitter = SerialTransmitter(
            config["transmitter"]["port"],
            config["transmitter"].get("baud", 115200),
            run_directory / "transmitter.log",
        )
        for setup_command in transmitter_commands(config):
            for attempt in range(3):
                try:
                    transmitter.command(setup_command)
                    break
                except TimeoutError:
                    if attempt == 2:
                        raise
                    time.sleep(0.5)

        receiver_process = subprocess.Popen(
            command,
            cwd=REPOSITORY_ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        if config["receiver"]["type"] == "pluto":
            wait_for_file(
                ready_file,
                receiver_process,
                config["receiver"].get("arm_timeout_s", 15),
            )
            time.sleep(config["receiver"].get("post_arm_delay_s", 0.25))
            if receiver_process.poll() is not None:
                stdout, stderr = receiver_process.communicate()
                raise RuntimeError(f"Pluto capture failed after arming\n{stdout}\n{stderr}")
        else:
            time.sleep(config["receiver"].get("arm_delay_s", 1.0))
            if receiver_process.poll() is not None:
                stdout, stderr = receiver_process.communicate()
                raise RuntimeError(f"RTL-SDR failed to start\n{stdout}\n{stderr}")

        interval_s = config["transmitter"]["packet_interval_ms"] / 1000
        for index in range(config["transmitter"]["packet_count"]):
            sent_utc = utc_now()
            lines = transmitter.command(
                "send",
                quiet_s=0.1,
                required_prefix="TX seq=",
                response_timeout_s=config["transmitter"].get("tx_timeout_s", 15),
            )
            tx_lines = [line for line in lines if line.startswith("TX seq=")]
            if not tx_lines or "state=0" not in tx_lines[-1]:
                raise RuntimeError(f"No successful TX confirmation for packet {index}")
            metadata["transmissions"].append(
                {"index": index, "host_utc": sent_utc, "radio_log": tx_lines[-1]}
            )
            if index + 1 < config["transmitter"]["packet_count"]:
                time.sleep(interval_s)

        timeout = config["receiver"]["duration_s"] + 20
        stdout, stderr = receiver_process.communicate(timeout=timeout)
        (run_directory / "receiver.stdout.log").write_text(stdout, encoding="utf-8")
        (run_directory / "receiver.stderr.log").write_text(stderr, encoding="utf-8")
        if receiver_process.returncode != 0:
            raise RuntimeError(f"Receiver failed with exit code {receiver_process.returncode}: {stderr}")

        captures = sorted(capture_directory.glob("*.cf32")) + sorted(
            capture_directory.glob("*.cu8")
        )
        if not captures:
            raise RuntimeError("Receiver completed but produced no IQ file")
        for capture in captures:
            metadata["captures"].append(
                {
                    "path": str(capture.relative_to(run_directory)),
                    "bytes": capture.stat().st_size,
                    "sha256": sha256(capture),
                }
            )

        analysis_enabled = config.get("analysis", {}).get("enabled", True)
        if analysis_enabled and not args.skip_analysis:
            matlab = config.get("analysis", {}).get("matlab_command", "matlab")
            for capture in captures:
                completed = subprocess.run(
                    [matlab, "-batch", matlab_expression(config, capture, analysis_directory)],
                    cwd=REPOSITORY_ROOT,
                    text=True,
                    capture_output=True,
                    check=False,
                )
                log_name = capture.stem + "-matlab.log"
                (analysis_directory / log_name).write_text(
                    completed.stdout + completed.stderr, encoding="utf-8"
                )
                if completed.returncode != 0:
                    raise RuntimeError(f"MATLAB analysis failed; see {log_name}")
                metadata["analysis"].append(
                    {"capture": capture.name, "matlab_log": f"analysis/{log_name}"}
                )

        metadata["status"] = "complete"
        metadata["completed_utc"] = utc_now()
        return run_directory
    except Exception as error:
        metadata["status"] = "failed"
        metadata["error"] = str(error)
        metadata["completed_utc"] = utc_now()
        if receiver_process is not None and receiver_process.poll() is None:
            receiver_process.terminate()
            try:
                stdout, stderr = receiver_process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                receiver_process.kill()
                stdout, stderr = receiver_process.communicate()
            (run_directory / "receiver.stdout.log").write_text(
                stdout, encoding="utf-8"
            )
            (run_directory / "receiver.stderr.log").write_text(
                stderr, encoding="utf-8"
            )
        raise
    finally:
        if transmitter is not None:
            transmitter.close()
        if ready_file.exists():
            ready_file.unlink()
        metadata_path.write_text(
            json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )


def main() -> None:
    try:
        output = run()
    except (KeyError, ValueError, RuntimeError, TimeoutError, subprocess.TimeoutExpired) as error:
        raise SystemExit(f"Experiment failed: {error}") from error
    print(f"Run directory: {output}")


if __name__ == "__main__":
    main()
