# Contributing

## Development workflow

1. Open an issue or describe the measurable outcome of the change.
2. Add or update the floating-point reference behavior.
3. Add deterministic tests, including at least one boundary or impairment case.
4. If RTL is involved, compare its output against versioned golden vectors.
5. Update the relevant architecture, experiment, or calibration notes.

Run the local checks before committing:

```bash
python -m pip install -e ".[dev]"
pytest
```

## Engineering conventions

- Store SI units in field names where ambiguity is possible (`sample_rate_hz`,
  `toa_s`, `position_m`).
- Record random seeds for generated signals and noise.
- Do not commit raw multi-megabyte captures; keep a small curated fixture or
  publish a checksum and retrieval note.
- Never overwrite raw experiment data. Derived results belong in a new output
  directory with their configuration and software revision.
- Document fixed-point scaling and rounding for every PL interface.
