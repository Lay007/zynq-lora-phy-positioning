# Documentation index

[Русская документация](ru/README.md)

## Start here

- [System architecture](architecture.md)
- [Roadmap and acceptance criteria](roadmap.md)
- [MATLAB modeling flow](../model/README.md)

## PHY algorithms and measurements

- **[BER/SER/PER methodology](ber-methodology.md)** — exact definitions for
  the uncoded and coded graphs, SNR convention, raw counts, and CSV outputs.
- **[Whitening, FEC, interleaving, and CRC](lora-phy-coding.md)** — implemented
  TX/RX ordering, equations, bit conventions, and acceptance tests.
- **[LoRa PHY Inspector](lora-phy-inspector.md)** — visual CU8/CF32 packet
  inspection, BW/SF/carrier/SNR estimation, and dechirped FFT display.

## Hardware and experiments

- [Hardware test bench](test-bench.md)
- [LR1121 to ZynqSDR hardware sweep, 2 August 2026](hardware-sweep-2026-08-02.md)
- **[SX1262 packet capture with RTL-SDR and PlutoSDR](iq-capture-guide.md)**
- **[One-machine transmit, capture, and analysis](automated-phy-experiment.md)**
- [Experiment workflow and provenance](../experiments/README.md)
