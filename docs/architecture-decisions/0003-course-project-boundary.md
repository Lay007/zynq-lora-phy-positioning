# ADR-0003: Keep the complete LoRa PHY separate from the educational CSS course path

**Status:** Accepted
**Date:** 2026-08-25

## Context

This repository and
[`zynq-sdr-course`](https://github.com/Lay007/zynq-sdr-course) both process chirp
signals. They have different validation targets: this project must demonstrate
LoRa interoperability, oversampled acquisition, packet behavior, ToA/TDoA and
board integration, while the course needs small readable examples that run in a
vendor-independent simulator.

Copying generated correlator HDL into the course would create two owners for the
same production design. Making either repository depend on a sibling checkout
would make clean-checkout reproduction fragile.

## Decision

- This repository remains authoritative for the complete LoRa PHY, SF5–SF12
  mode coverage, the oversampled two-FFT correlator, packet synchronization and
  coding, timestamp metadata, ToA/TDoA and hardware evidence.
- The course owns an independent generic CSS learning path and a compact SF7
  sequential detector. It may link to this design but does not claim LoRa
  interoperability from that baseline.
- Generated HDL is not copied between repositories.
- Cross-project comparisons must declare scaling. The generated correlator
  currently accepts signed 16-bit IQ with 10 fractional bits; the course
  baseline uses Q1.15.
- Shared material, if introduced later, is limited to versioned vector schemas
  or small language-neutral fixtures. Neither repository gains a runtime
  dependency on the other.

## Consequences

- Each repository remains independently reproducible.
- Educational RTL can favor clarity without constraining the production
  correlator architecture.
- Production LoRa acceptance and RF claims have one canonical evidence trail.
- Arithmetic or vector comparisons need an explicit conversion step rather than
  relying on equal port widths.
