#!/usr/bin/env python3
"""Summarise one capture run directory (clg400-trace-*.json).

One line of counts per stage that a campaign has to keep apart: attempts,
captured, failed (by the stage that failed), CRC-valid, packets the detector
accepted only through its straddle-tolerant path (joint status bit 5, M7) and
what became of those. A failed attempt carries the IQ's burst ratio when the
recording finished, which is what separates "no packet on the air" from "the
packet was there and the PL never detected it".

    python tools/summarize_capture_run.py experiments/runs/<run>
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path


def load_records(run_dir: Path) -> list[dict[str, object]]:
    records = []
    for path in sorted(run_dir.glob("clg400-trace-*.json")):
        record = json.loads(path.read_text(encoding="utf-8"))
        record["_file"] = path.name
        records.append(record)
    return records


def summarize(records: list[dict[str, object]], min_burst_ratio: float = 50.0) -> dict[str, object]:
    failed = [r for r in records if r.get("status") == "failed"]
    captured = [r for r in records if r.get("status") != "failed"]

    by_stage = Counter(str(r.get("stage")) for r in failed)
    undetected = [
        r
        for r in failed
        if r.get("stage") == "read_trace"
        and float(r.get("iq_burst_ratio") or 0.0) >= min_burst_ratio
    ]
    no_packet = [
        r
        for r in failed
        if r.get("stage") == "read_trace"
        and r.get("iq_burst_ratio") is not None
        and float(r["iq_burst_ratio"]) < min_burst_ratio
    ]

    crc_valid = [r for r in captured if r["decode"]["crc_valid"]]
    straddled = [
        r for r in captured if r.get("joint_estimate", {}).get("detector_straddle_accepted")
    ]
    plain = [r for r in captured if r not in straddled]

    def rate(part: list, whole: list) -> str:
        return f"{len(part)}/{len(whole)}" + (
            f" ({100.0 * len(part) / len(whole):.0f}%)" if whole else ""
        )

    return {
        "attempts": len(records),
        "captured": len(captured),
        "failed": len(failed),
        "failed_by_stage": dict(by_stage),
        "undetected_but_packet_in_recording": len(undetected),
        "no_packet_in_recording": len(no_packet),
        "crc_valid": rate(crc_valid, captured),
        "straddle_accepted": len(straddled),
        "straddle_accepted_crc_valid": rate(
            [r for r in straddled if r["decode"]["crc_valid"]], straddled
        ),
        "straddle_accepted_precise_applied": rate(
            [
                r
                for r in straddled
                if r["joint_estimate"]["precise_correction_applied"]
            ],
            straddled,
        ),
        "not_straddle_crc_valid": rate(
            [r for r in plain if r["decode"]["crc_valid"]], plain
        ),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("run_dir", type=Path)
    parser.add_argument("--min-burst-ratio", type=float, default=50.0)
    args = parser.parse_args()
    summary = summarize(load_records(args.run_dir), args.min_burst_ratio)
    for key, value in summary.items():
        print(f"{key:38s} {value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
