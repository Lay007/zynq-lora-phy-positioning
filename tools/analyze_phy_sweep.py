"""Analyze completed hardware sweep captures in one MATLAB batch session."""

from __future__ import annotations

import argparse
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def matlab_quote(value: Path) -> str:
    return str(value.resolve()).replace("\\", "/").replace("'", "''")


def completed_runs(sweep_directories: list[Path]) -> list[dict[str, Any]]:
    runs = []
    for sweep_directory in sweep_directories:
        manifest = json.loads(
            (sweep_directory / "sweep-result.json").read_text(encoding="utf-8")
        )
        for case in manifest["cases"]:
            if case["status"] != "complete":
                continue
            run_directory = Path(case["run_directory"])
            result = json.loads((run_directory / "run.json").read_text(encoding="utf-8"))
            capture = run_directory / result["captures"][0]["path"]
            runs.append(
                {
                    "name": case["name"],
                    "run_directory": run_directory,
                    "capture": capture,
                    "sample_rate_hz": result["config"]["receiver"]["sample_rate_hz"],
                    "centre_frequency_hz": result["config"]["receiver"]["center_frequency_hz"],
                    "signal_frequency_hz": result["config"]["transmitter"]["frequency_hz"],
                    "bandwidth_hz": result["config"]["transmitter"]["bandwidth_hz"],
                    "spreading_factor": result["config"]["transmitter"]["spreading_factor"],
                }
            )
    return runs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sweep_directories", type=Path, nargs="+")
    parser.add_argument("--matlab", default="matlab")
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    runs = completed_runs([path.resolve() for path in args.sweep_directories])
    if not runs:
        raise SystemExit("No completed captures found")
    args.output.mkdir(parents=True, exist_ok=True)
    driver = args.output / "analyze_sweep_generated.m"
    lines = [
        f"cd('{matlab_quote(ROOT / 'model' / 'matlab')}');",
        "failures = strings(0);",
    ]
    for run in runs:
        analysis = run["run_directory"] / "analysis"
        analysis.mkdir(exist_ok=True)
        call = (
            f"analyze_iq_capture('{matlab_quote(run['capture'])}','cf32',"
            f"{run['sample_rate_hz']},{run['centre_frequency_hz']},"
            f"{run['signal_frequency_hz']},'{matlab_quote(analysis)}',"
            f"ExpectedBandwidthHz={run['bandwidth_hz']},"
            f"ExpectedSpreadingFactor={run['spreading_factor']});"
        )
        name = str(run["name"]).replace("'", "''")
        lines.extend(
            [
                f"fprintf('ANALYZE {name}\\n');",
                "try",
                f"  {call}",
                "catch error",
                f"  failures(end+1) = \"{name}: \" + string(getReport(error, 'basic'));",
                "end",
            ]
        )
    lines.extend(
        [
            "if ~isempty(failures)",
            "  disp(failures');",
            "  error('Sweep analysis had %d failure(s)', numel(failures));",
            "end",
        ]
    )
    driver.write_text("\n".join(lines) + "\n", encoding="utf-8")
    completed = subprocess.run(
        [args.matlab, "-batch", f"run('{matlab_quote(driver)}')"],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    (args.output / "matlab.log").write_text(
        completed.stdout + completed.stderr, encoding="utf-8"
    )
    records = []
    for run in runs:
        reports = sorted((run["run_directory"] / "analysis").glob("*-inspection.json"))
        records.append(
            {
                "name": run["name"],
                "run_directory": str(run["run_directory"]),
                "report": str(reports[-1]) if reports else None,
                "status": "complete" if reports else "failed",
            }
        )
    summary = {
        "schema": "zynq-lora-phy-sweep-analysis-v1",
        "completed_utc": datetime.now(timezone.utc).isoformat(),
        "matlab_returncode": completed.returncode,
        "captures": records,
    }
    (args.output / "analysis-result.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"Analyzed {sum(r['status'] == 'complete' for r in records)}/{len(records)} captures")
    print(f"Summary: {args.output / 'analysis-result.json'}")
    if completed.returncode != 0 or any(r["status"] != "complete" for r in records):
        raise SystemExit("Sweep analysis failed; inspect matlab.log")


if __name__ == "__main__":
    main()
