# Reproducible experiments

Create one immutable configuration per run by copying the relevant template:

```text
experiments/templates/toa.yaml
experiments/templates/tdoa.yaml
experiments/templates/phy-capture.yaml
        ↓ copy and fill
experiments/runs/2026-08-01_toa_cable_001.yaml
        ↓ execute
artifacts/2026-08-01_toa_cable_001/
```

Generated `artifacts/` and full IQ captures are ignored by Git. Commit the
completed run configuration, compact result tables, plots, and checksums for
external raw data when the experiment contributes project evidence.

## Required provenance

- exact repository commit and dirty/clean state;
- board, RFIC, firmware, bitstream, and host software revisions;
- waveform and RF settings with explicit units;
- clock/epoch topology and calibration identifier;
- receiver coordinates and coordinate frame for TDoA;
- random seed for simulations;
- raw-data paths and SHA-256 checksums;
- acceptance criterion chosen before the run.

Use `phy-capture.yaml` for raw RTL-SDR or PlutoSDR recordings made to validate
the MATLAB LoRa packet model before starting timestamp experiments.

For a synchronized host-controlled PHY run, copy one of the JSON files in
`configs/` to a machine-local `*.local.json` file and use
`tools/run_phy_experiment.py`. It configures the serial transmitter, arms the
SDR, sends acknowledged packets, records checksums and logs, and launches the
MATLAB inspection report. See the
[one-machine workflow](../docs/automated-phy-experiment.md).

Do not edit raw results after acquisition. If processing changes, create a new
analysis output that points to the same immutable source capture.
