"""Capture finite, gap-free PlutoSDR IQ buffers with reproducible metadata.

Install the optional hardware dependencies before use:
    python -m pip install pyadi-iio pylibiio
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np


_dll_directory_handle = None


def prepare_windows_libiio() -> None:
    """Prefer a venv-local libiio over unrelated SDR applications on PATH."""
    global _dll_directory_handle
    if os.name != "nt":
        return
    candidates = []
    if os.environ.get("LIBIIO_DLL_DIR"):
        candidates.append(Path(os.environ["LIBIIO_DLL_DIR"]))
    candidates.append(Path(sys.executable).resolve().parent)
    for directory in candidates:
        if (directory / "libiio.dll").is_file():
            os.environ["PATH"] = str(directory) + os.pathsep + os.environ["PATH"]
            if hasattr(os, "add_dll_directory"):
                _dll_directory_handle = os.add_dll_directory(str(directory))
            return


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--uri", default="ip:192.168.2.1")
    parser.add_argument("--signal-frequency", type=int, required=True)
    parser.add_argument("--center-frequency", type=int, required=True)
    parser.add_argument("--sample-rate", type=int, default=1_000_000)
    parser.add_argument("--rf-bandwidth", type=int, default=1_000_000)
    parser.add_argument("--gain", type=float, default=20.0)
    parser.add_argument("--samples", type=int, default=2**22)
    parser.add_argument("--count", type=int, default=5)
    parser.add_argument("--warmup", type=int, default=2)
    parser.add_argument(
        "--timeout-ms",
        type=int,
        default=30_000,
        help="IIO operation timeout; must exceed a full buffer acquisition",
    )
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--ready-file",
        type=Path,
        help="Create this file after RX configuration and warm-up are complete",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    prepare_windows_libiio()
    try:
        import adi
    except ImportError as error:
        raise SystemExit(
            "Pluto support is missing. Install pyadi-iio and pylibiio."
        ) from error

    args.output.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc)
    run_id = started.strftime("%Y%m%dT%H%M%S.%fZ")

    if args.timeout_ms <= 0:
        raise SystemExit("--timeout-ms must be positive")

    radio = adi.Pluto(uri=args.uri)
    radio._ctx.set_timeout(args.timeout_ms)
    radio.sample_rate = args.sample_rate
    radio.rx_lo = args.center_frequency
    radio.rx_rf_bandwidth = args.rf_bandwidth
    radio.gain_control_mode_chan0 = "manual"
    radio.rx_hardwaregain_chan0 = args.gain
    radio.rx_buffer_size = args.samples
    context_attributes = dict(getattr(radio._ctx, "attrs", {}))

    # A single kernel buffer avoids returning stale buffers after reconfiguration.
    if hasattr(radio, "_rxadc"):
        radio._rxadc.set_kernel_buffers_count(1)

    for _ in range(args.warmup):
        radio.rx()

    if args.ready_file is not None:
        args.ready_file.parent.mkdir(parents=True, exist_ok=True)
        args.ready_file.write_text(
            datetime.now(timezone.utc).isoformat() + "\n", encoding="utf-8"
        )

    files: list[dict[str, object]] = []
    for capture_index in range(args.count):
        iq = np.asarray(radio.rx(), dtype=np.complex64)
        filename = f"pluto-{run_id}-{capture_index:03d}.cf32"
        path = args.output / filename
        interleaved = np.empty(2 * iq.size, dtype="<f4")
        interleaved[0::2] = iq.real
        interleaved[1::2] = iq.imag
        interleaved.tofile(path)
        files.append(
            {
                "path": filename,
                "samples": int(iq.size),
                "sha256": sha256(path),
            }
        )

    metadata = {
        "schema": "zynq-lora-phy-capture-v1",
        "started_utc": started.isoformat(),
        "device": context_attributes.get("hw_model", "Pluto-compatible IIO SDR"),
        "firmware_version": context_attributes.get("fw_version"),
        "uri": args.uri,
        "sample_format": "complex-float32-le-iq",
        "signal_frequency_hz": args.signal_frequency,
        "center_frequency_hz": int(radio.rx_lo),
        "digital_shift_to_baseband_hz": int(radio.rx_lo) - args.signal_frequency,
        "sample_rate_hz": int(radio.sample_rate),
        "rf_bandwidth_hz": int(radio.rx_rf_bandwidth),
        "gain_mode": "manual",
        "gain_db": float(radio.rx_hardwaregain_chan0),
        "iio_timeout_ms": args.timeout_ms,
        "buffer_samples": args.samples,
        "buffers_are_individually_contiguous": True,
        "gaps_may_exist_between_files": True,
        "files": files,
    }
    metadata_path = args.output / f"pluto-{run_id}-metadata.json"
    metadata_path.write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    radio.rx_destroy_buffer()
    print(metadata_path)


if __name__ == "__main__":
    main()
