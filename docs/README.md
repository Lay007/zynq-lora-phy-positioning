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

- [CLG400 LoRa receiver bring-up](clg400-hardware-bring-up.md)
- [CLG400 cold boot and first OTA acquisition — 2026-09-02](clg400-hardware-session-2026-09-02.md)
- [CLG400 frozen symbol trace and hard packet decoder](clg400-symbol-trace.md)
- [CLG400 symbol trace and first decoded payload — 2026-09-03](clg400-payload-session-2026-09-03.md)
- [CLG400 accepted over-the-air payload evidence](data/clg400-symbol-trace-2026-09-03.json)
- [CLG400 realigned-grid evidence](data/clg400-grid-resync-2026-09-04.json)
- [CLG400 board-level synthesis evidence](data/rtl-m4-clg400-board-synthesis.csv)
- [CLG400 board-level implementation evidence](data/rtl-m4-clg400-board-implementation.csv)
- [CLG400 offline boot-package evidence](data/rtl-m4-clg400-board-boot-package.csv)
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
