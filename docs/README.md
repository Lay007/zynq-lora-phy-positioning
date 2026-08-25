# Documentation index

This directory contains the engineering documentation for the LoRa PHY and positioning project.

## Core architecture and implementation

- [Architecture](architecture.md)
- [Roadmap](roadmap.md)
- [LoRa PHY coding](lora-phy-coding.md)
- [LoRa PHY inspector](lora-phy-inspector.md)
- [AXI4-Lite control/status register map](axi-lite-register-map.md)

## Measurement and verification

- [BER methodology](ber-methodology.md)
- [IQ capture guide](iq-capture-guide.md)
- [Automated PHY experiment](automated-phy-experiment.md)

## Hardware evidence

- [Hardware sweep — 2026-08-02](hardware-sweep-2026-08-02.md)
- [Heltec V4.3 hardware sweep — 2026-08-03](hardware-sweep-2026-08-03-heltec-v43.md)
- [Targeted hardware notes — 2026-08-07](hardware-targeted-2026-08-07.md)

## Evidence boundary

The repository deliberately separates four evidence layers:

1. floating-point / fixed-point model evidence;
2. generated-HDL and RTL simulation evidence;
3. integration-wrapper and implementation evidence;
4. board-level Zynq/AD936x measurement evidence.

A passing AXI-Lite or metadata-wrapper simulation proves register/integration RTL behavior only. It must not be described as proof of board-level LoRa reception, timing accuracy, or positioning performance until the corresponding hardware experiment exists.
