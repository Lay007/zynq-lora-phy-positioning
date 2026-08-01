# Zynq LoRa PHY and Positioning

FPGA/SDR implementation of LoRa communication, precise time-of-arrival (ToA)
estimation, and time-difference-of-arrival (TDoA) positioning.

The project is an engineering and research platform, not a replacement for a
low-power commercial LoRa transceiver. Its purpose is to expose the complete
PHY processing chain, make internal measurements observable, and provide a
repeatable path from a floating-point reference model to a ZynqSDR
implementation.

> Status: project scaffold and executable Python reference model. RTL and board
> support are planned; the repository does not yet contain a hardware LoRa
> receiver.

## Project goals

- Receive and transmit LoRa-compatible packets with a ZynqSDR platform.
- Build a traceable implementation path: float model → fixed-point model → RTL.
- Estimate timing, CFO, SFO, RSSI, and SNR in addition to decoded payloads.
- Timestamp packet arrivals in programmable logic on multiple synchronized
  receivers.
- Measure and calibrate systematic channel delays before solving 2D TDoA.
- Keep experiments reproducible through versioned configurations, captures,
  metrics, and reports.

The first hardware milestone is deliberately narrow:

> Capture an SX1262 transmission with ZynqSDR and use the Python model to detect
> its preamble, estimate CFO, and recover every LoRa symbol at BW 125 kHz and
> SF7. Then reproduce dechirp, FFT, and peak detection in PL using the same test
> vectors.

## Current contents

- `src/zynq_lora_phy/` — NumPy CSS/LoRa primitives, channel impairments, ToA,
  and TDoA reference functions.
- `tests/` — deterministic unit tests for symbol recovery, impairments, ToA,
  and multilateration.
- `docs/` — architecture, development roadmap, and test-bench requirements.
- `experiments/templates/` — versioned metadata templates for ToA and TDoA
  measurements.
- `fpga/`, `firmware/`, and `hardware/` — integration boundaries for later
  PL, PS, and board-specific work.

## Quick start

Python 3.10 or newer is recommended.

```bash
python -m venv .venv
python -m pip install -e ".[dev]"
pytest
python examples/css_roundtrip.py
```

The example generates deterministic CSS symbols, applies AWGN and carrier
frequency offset, compensates the known offset, and demodulates the symbols.

## Repository layout

```text
.
├── docs/                   Architecture, roadmap, and bench requirements
├── examples/               Small executable reference-model examples
├── experiments/
│   └── templates/          ToA/TDoA experiment metadata
├── captures/               Local raw IQ captures (large data ignored by Git)
├── fpga/                   PL/RTL sources, constraints, and verification
├── firmware/               Zynq PS software and host control
├── hardware/               Board notes, clocking, and calibration data
├── src/zynq_lora_phy/      Python reference package
└── tests/                  Automated tests
```

## Architecture and plan

- [System architecture](docs/architecture.md)
- [Roadmap and acceptance criteria](docs/roadmap.md)
- [Hardware test bench](docs/test-bench.md)
- [Experiment workflow](experiments/README.md)

## Measurement principles

1. Validate algorithms in simulation before using RF captures.
2. Compare float, fixed-point, RTL, and hardware with identical test vectors.
3. Generate precise timestamps in PL, never from Linux or network arrival time.
4. Treat cable, splitter, RF, ADC, and DSP delays as calibrated quantities.
5. Record configuration and provenance with every result.

## Contributing

Keep changes small and measurable. New DSP blocks should include a reference
model, deterministic tests, numerical tolerances, and a documented hardware
mapping. See [CONTRIBUTING.md](CONTRIBUTING.md).
