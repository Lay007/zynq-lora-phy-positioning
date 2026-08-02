"""Run a validated matrix of one-machine LoRa PHY experiments."""

from __future__ import annotations

import argparse
import copy
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def deep_merge(target: dict[str, Any], changes: dict[str, Any]) -> None:
    for key, value in changes.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = value


def load_runner():
    import importlib.util

    path = ROOT / "tools" / "run_phy_experiment.py"
    spec = importlib.util.spec_from_file_location("run_phy_experiment", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepare_cases(
    sweep: dict[str, Any], base: dict[str, Any], execute: bool
) -> list[tuple[str, dict[str, Any]]]:
    if sweep.get("schema") != "zynq-lora-phy-sweep-v1":
        raise ValueError("Unsupported or missing sweep schema")
    prefix = sweep.get("name", "phy-sweep")
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", prefix):
        raise ValueError("Sweep name contains unsupported characters")
    runner = load_runner()
    prepared = []
    names: set[str] = set()
    for entry in sweep.get("cases", []):
        name = entry.get("name", "")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", name):
            raise ValueError(f"Invalid case name: {name!r}")
        if name in names:
            raise ValueError(f"Duplicate case name: {name}")
        names.add(name)
        config = copy.deepcopy(base)
        deep_merge(config, entry.get("overrides", {}))
        config["run_name"] = f"{prefix}-{name}"
        runner.validate_config(config)
        if execute:
            runner.validate_execution_config(config)
        prepared.append((name, config))
    if not prepared:
        raise ValueError("Sweep contains no cases")
    return prepared


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sweep", type=Path, required=True)
    parser.add_argument("--base-config", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, default=ROOT / "artifacts" / "phy-sweeps")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--analyze", action="store_true", help="Run MATLAB after every capture")
    parser.add_argument("--continue-on-error", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.dry_run == args.execute:
        raise SystemExit("Choose exactly one of --dry-run or --execute")
    sweep = json.loads(args.sweep.read_text(encoding="utf-8"))
    base = json.loads(args.base_config.read_text(encoding="utf-8"))
    cases = prepare_cases(sweep, base, args.execute)

    started = datetime.now(timezone.utc)
    sweep_id = f"{started.strftime('%Y%m%dT%H%M%SZ')}-{sweep['name']}"
    directory = args.output_root.resolve() / sweep_id
    directory.mkdir(parents=True, exist_ok=False)
    configs = directory / "configs"
    runs = directory / "runs"
    configs.mkdir()
    runs.mkdir()
    manifest = {
        "schema": "zynq-lora-phy-sweep-result-v1",
        "sweep_id": sweep_id,
        "started_utc": started.isoformat(),
        "definition": str(args.sweep.resolve()),
        "base_config": str(args.base_config.resolve()),
        "analysis_during_capture": args.analyze,
        "cases": [],
        "status": "running",
    }
    manifest_path = directory / "sweep-result.json"

    failures = 0
    try:
        for index, (name, config) in enumerate(cases, start=1):
            config_path = configs / f"{index:02d}-{name}.json"
            config_path.write_text(
                json.dumps(config, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            record = {
                "index": index,
                "name": name,
                "config": str(config_path.relative_to(directory)),
                "started_utc": utc_now(),
                "status": "running",
            }
            manifest["cases"].append(record)
            manifest_path.write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            print(f"\n=== [{index}/{len(cases)}] {name} ===", flush=True)
            command = [
                sys.executable,
                str(ROOT / "tools" / "run_phy_experiment.py"),
                "--config",
                str(config_path),
                "--output-root",
                str(runs),
                "--execute" if args.execute else "--dry-run",
            ]
            if not args.analyze:
                command.append("--skip-analysis")
            process = subprocess.Popen(
                command,
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            output: list[str] = []
            assert process.stdout is not None
            for line in process.stdout:
                print(line, end="", flush=True)
                output.append(line)
            returncode = process.wait()
            log_path = directory / f"{index:02d}-{name}.log"
            log_path.write_text("".join(output), encoding="utf-8")
            run_lines = [line for line in output if line.startswith("Run directory:")]
            record.update(
                {
                    "completed_utc": utc_now(),
                    "status": "complete" if returncode == 0 else "failed",
                    "returncode": returncode,
                    "log": str(log_path.relative_to(directory)),
                    "run_directory": run_lines[-1].split(":", 1)[1].strip()
                    if run_lines
                    else None,
                }
            )
            manifest_path.write_text(
                json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            if returncode != 0:
                failures += 1
                if not args.continue_on_error:
                    break
    finally:
        manifest["completed_utc"] = utc_now()
        if failures:
            manifest["status"] = "partial" if failures < len(cases) else "failed"
        else:
            manifest["status"] = "complete"
        manifest["completed_cases"] = sum(
            case["status"] == "complete" for case in manifest["cases"]
        )
        manifest["failed_cases"] = failures
        manifest_path.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
    print(f"Sweep directory: {directory}")
    if failures:
        raise SystemExit(f"Sweep completed with {failures} failed case(s)")


if __name__ == "__main__":
    main()
