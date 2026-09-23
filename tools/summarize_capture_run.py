#!/usr/bin/env python3
"""Summarise one capture run directory (clg400-trace-*.json).

One line of counts per stage that a campaign has to keep apart: attempts,
captured, failed (by the stage that failed), CRC-valid, packets the detector
accepted only through its straddle-tolerant path (joint status bit 5, M7) and
what became of those. A failed attempt carries the IQ's burst ratio when the
recording finished, which is what separates "no packet on the air" from "the
packet was there and the PL never detected it". On the M8 diagnostic image
every record also carries the receive crossing's drop count since boot; the
summary reports how many samples the series lost and between which attempts,
and on which misses the decision history was read.

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


def _drop_count(record: dict[str, object]) -> int | None:
    if record.get("status") == "failed":
        value = (record.get("pl_state") or {}).get("crossing_drop_count")
    else:
        value = (record.get("receiver_clock") or {}).get("crossing_drop_count")
    return None if value is None else int(value)


def drop_increments(records: list[dict[str, object]]) -> list[tuple[str, str, int]]:
    """(previous file, file, samples dropped between them), where any were.

    The count is cumulative since boot and read once per attempt, so an
    increase between two consecutive readings puts the loss inside the later
    attempt (or the gap before it).
    """

    increments = []
    previous: tuple[str, int] | None = None
    for record in records:
        count = _drop_count(record)
        if count is None:
            continue
        if previous is not None and count != previous[1]:
            increments.append((previous[0], str(record["_file"]), (count - previous[1]) & 0xFFFF))
        previous = (str(record["_file"]), count)
    return increments


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
        "crossing_drop_increments": [
            f"{b}: +{n}" for _, b, n in drop_increments(records)
        ] if any(_drop_count(r) is not None for r in records) else "n/a (image without the count)",
        "misses_with_decision_history": [
            str(r["_file"]) for r in undetected if r.get("decision_history")
        ],
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
