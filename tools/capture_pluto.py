"""Capture finite, gap-free PlutoSDR IQ buffers with reproducible metadata.

Install the optional hardware dependencies before use:
    python -m pip install pyadi-iio pylibiio
"""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np


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
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        import adi
    except ImportError as error:
        raise SystemExit(
            "Pluto support is missing. Install pyadi-iio and pylibiio."
        ) from error

    args.output.mkdir(parents=True, exist_ok=True)
    started = datetime.now(timezone.utc)
    run_id = started.strftime("%Y%m%dT%H%M%S.%fZ")

    radio = adi.Pluto(uri=args.uri)
    radio.sample_rate = args.sample_rate
    radio.rx_lo = args.center_frequency
    radio.rx_rf_bandwidth = args.rf_bandwidth
    radio.gain_control_mode_chan0 = "manual"
    radio.rx_hardwaregain_chan0 = args.gain
    radio.rx_buffer_size = args.samples

    # A single kernel buffer avoids returning stale buffers after reconfiguration.
    if hasattr(radio, "_rxadc"):
        radio._rxadc.set_kernel_buffers_count(1)

    for _ in range(args.warmup):
        radio.rx()

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
        "device": "ADALM-Pluto",
        "uri": args.uri,
        "sample_format": "complex-float32-le-iq",
        "signal_frequency_hz": args.signal_frequency,
        "center_frequency_hz": int(radio.rx_lo),
        "digital_shift_to_baseband_hz": int(
            args.center_frequency - args.signal_frequency
        ),
        "sample_rate_hz": int(radio.sample_rate),
        "rf_bandwidth_hz": int(radio.rx_rf_bandwidth),
        "gain_mode": "manual",
        "gain_db": float(radio.rx_hardwaregain_chan0),
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
