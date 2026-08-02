# Contributing

## Development workflow

1. Open an issue or describe the measurable outcome of the change.
2. Add or update the authoritative MATLAB floating-point behavior.
3. Add deterministic MATLAB tests, including a boundary or impairment case.
4. Update the Simulink implementation only after the MATLAB behavior is stable.
5. Compare generated Verilog against versioned MATLAB/Simulink golden vectors.
6. Update the relevant architecture, experiment, or calibration notes.

Run the local checks before committing:

```bash
python -m pip install -e ".[dev]"
pytest
```

For the authoritative model, run in MATLAB:

```matlab
cd model/matlab
results = run_tests;
assertSuccess(results);
```

## Engineering conventions

- Store SI units in field names where ambiguity is possible (`sample_rate_hz`,
  `toa_s`, `position_m`).
- Record random seeds for generated signals and noise.
- Keep generated runs under ignored `artifacts/`. Promote only reviewed,
  redistributable IQ evidence to `captures/reference/`; raw `.cf32`, `.cu8`,
  and `.cfile` data there must use Git LFS and include provenance plus SHA-256.
- Never overwrite raw experiment data. Derived results belong in a new output
  directory with their configuration and software revision.
- Document fixed-point scaling and rounding for every PL interface.
- Do not edit HDL Coder output manually; change the Simulink source or its HDL
  configuration and regenerate Verilog.
