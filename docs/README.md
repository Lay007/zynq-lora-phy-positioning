# Documentation index

[Русская документация](ru/README.md)

## Start here

- [System architecture](architecture.md)
- [Roadmap and acceptance criteria](roadmap.md)
- [Completed MATLAB M1 floating-point acceptance](matlab-m1-acceptance.md)
- [MATLAB modeling flow](../model/README.md)
- [M2 foundations: toolchain, interfaces, and stage vectors](simulink-m2-interfaces.md)
- [M2 acceptance: Simulink measurements](simulink-m2-acceptance.md)
- [ADR-0001: coherent FFT correlator and fallback](architecture-decisions/0001-coherent-css-demodulator.md)

## PHY algorithms and measurements

- **[BER/SER/PER methodology](ber-methodology.md)** — exact definitions for
  the uncoded and coded graphs, SNR convention, raw counts, and CSV outputs.
- **[Whitening, FEC, interleaving, and CRC](lora-phy-coding.md)** — implemented
  TX/RX ordering, equations, bit conventions, and acceptance tests.
- **[LoRa PHY Inspector](lora-phy-inspector.md)** — visual CU8/CF32 packet
  inspection, BW/SF/carrier/SNR estimation, and dechirped FFT display.
- **[Fractional ToA methodology](toa-methodology.md)** — normalized matched
  filtering, sub-sample interpolation, reproducible AWGN metrics, and the
  hardware calibration sequence.
- **[MATLAB M1 acceptance](matlab-m1-acceptance.md)** — continuous-packet
  acquisition/PER, all SF/CR pairs, impairments, real IQ, and calibrated 2D
  TDoA evidence.

## Hardware and experiments

- [Hardware test bench](test-bench.md)
- [Heltec V4.3/SX1262 to ZynqSDR hardware sweep, 3 August 2026](hardware-sweep-2026-08-03-heltec-v43.md)
- [Targeted Heltec V4.3 low-SF, BW500, and ToA run, 7 August 2026](hardware-targeted-2026-08-07.md)
- [LR1121 to ZynqSDR hardware sweep, 2 August 2026](hardware-sweep-2026-08-02.md)
- **[SX1262 packet capture with RTL-SDR and PlutoSDR](iq-capture-guide.md)**
- **[One-machine transmit, capture, and analysis](automated-phy-experiment.md)**
- [Experiment workflow and provenance](../experiments/README.md)
