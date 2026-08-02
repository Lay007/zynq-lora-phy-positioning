"""Promote validated sweep captures into a reproducible Git LFS dataset."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def completed_cases(sweep_directories: list[Path]) -> list[dict[str, Any]]:
    cases: dict[str, dict[str, Any]] = {}
    for sweep_directory in sweep_directories:
        sweep = json.loads(
            (sweep_directory / "sweep-result.json").read_text(encoding="utf-8")
        )
        for case in sweep["cases"]:
            if case["status"] != "complete":
                continue
            name = case["name"]
            if name in cases:
                raise ValueError(f"Duplicate completed case: {name}")
            run_directory = Path(case["run_directory"])
            result = json.loads(
                (run_directory / "run.json").read_text(encoding="utf-8")
            )
            if result["status"] != "complete" or len(result["captures"]) != 1:
                raise ValueError(f"Case {name} does not have one complete capture")
            cases[name] = {
                "name": name,
                "sweep_directory": sweep_directory,
                "run_directory": run_directory,
                "result": result,
            }
    return list(cases.values())


def analysis_for(run_directory: Path) -> dict[str, Any] | None:
    reports = sorted((run_directory / "analysis").glob("*-inspection.json"))
    if not reports:
        return None
    report = json.loads(reports[-1].read_text(encoding="utf-8"))
    fields = (
        "packet_start_seconds",
        "packet_end_seconds",
        "estimated_bandwidth_hz",
        "measured_occupied_bandwidth_hz",
        "estimated_spreading_factor",
        "estimated_symbol_duration_seconds",
        "estimated_carrier_hz",
        "cfo_hz",
        "estimated_snr_db",
        "preamble_score",
        "profile_constrained",
        "expected_bandwidth_hz",
        "expected_spreading_factor",
    )
    return {field: report[field] for field in fields if field in report}


def write_summary(records: list[dict[str, Any]], path: Path) -> None:
    fields = (
        "name",
        "spreading_factor",
        "bandwidth_hz",
        "coding_rate",
        "power_dbm",
        "payload_length",
        "preamble_symbols",
        "crc_enabled",
        "iq_inverted",
        "packet_count",
        "capture_bytes",
        "sha256",
        "estimated_snr_db",
        "cfo_hz",
        "packet_start_seconds",
        "packet_end_seconds",
    )
    with path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        for record in records:
            transmitter = record["transmitter"]
            analysis = record["analysis"] or {}
            writer.writerow(
                {
                    "name": record["name"],
                    "spreading_factor": transmitter["spreading_factor"],
                    "bandwidth_hz": transmitter["bandwidth_hz"],
                    "coding_rate": f"4/{transmitter['coding_rate_denominator']}",
                    "power_dbm": transmitter["power_dbm"],
                    "payload_length": transmitter["payload_length"],
                    "preamble_symbols": transmitter["preamble_symbols"],
                    "crc_enabled": transmitter["crc_enabled"],
                    "iq_inverted": transmitter["iq_inverted"],
                    "packet_count": len(record["transmissions"]),
                    "capture_bytes": record["capture"]["bytes"],
                    "sha256": record["capture"]["sha256"],
                    "estimated_snr_db": analysis.get("estimated_snr_db", ""),
                    "cfo_hz": analysis.get("cfo_hz", ""),
                    "packet_start_seconds": analysis.get("packet_start_seconds", ""),
                    "packet_end_seconds": analysis.get("packet_end_seconds", ""),
                }
            )


def curate(cases: list[dict[str, Any]], output: Path) -> dict[str, Any]:
    output.mkdir(parents=True, exist_ok=False)
    records = []
    for case in cases:
        result = case["result"]
        source_record = result["captures"][0]
        source = case["run_directory"] / source_record["path"]
        if source.stat().st_size != source_record["bytes"]:
            raise ValueError(f"Size mismatch for {case['name']}: {source}")
        actual_sha256 = sha256_file(source)
        if actual_sha256.lower() != source_record["sha256"].lower():
            raise ValueError(f"SHA-256 mismatch for {case['name']}: {source}")

        target = output / f"{case['name']}.cf32"
        shutil.copy2(source, target)
        if sha256_file(target) != actual_sha256:
            raise ValueError(f"Copy verification failed for {case['name']}: {target}")

        config = result["config"]
        records.append(
            {
                "name": case["name"],
                "capture": {
                    "path": target.name,
                    "sha256": actual_sha256,
                    "bytes": source_record["bytes"],
                    "samples": source_record["bytes"] // 8,
                    "format": "complex-float32-le-iq",
                },
                "transmitter": config["transmitter"],
                "receiver": config["receiver"],
                "bench": config["bench"],
                "transmissions": result["transmissions"],
                "analysis": analysis_for(case["run_directory"]),
                "provenance": {
                    "source_run_id": result["run_id"],
                    "repository_commit_at_acquisition": result["repository_commit"],
                    "repository_was_dirty": result["repository_dirty"],
                },
            }
        )

    manifest = {
        "schema": "zynq-lora-reference-sweep-v1",
        "curated_utc": datetime.now(timezone.utc).isoformat(),
        "capture_count": len(records),
        "total_bytes": sum(record["capture"]["bytes"] for record in records),
        "captures": records,
        "notes": [
            "Raw IQ samples are byte-identical to the source experiment captures.",
            "This is an OTA engineering dataset, not a calibrated RF measurement.",
        ],
    }
    (output / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    write_summary(records, output / "summary.csv")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sweep_directories", type=Path, nargs="+")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    cases = completed_cases([path.resolve() for path in args.sweep_directories])
    manifest = curate(cases, args.output.resolve())
    print(
        f"Curated {manifest['capture_count']} captures, "
        f"{manifest['total_bytes']} bytes into {args.output.resolve()}"
    )


if __name__ == "__main__":
    main()
