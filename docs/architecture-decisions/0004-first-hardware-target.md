# ADR-0004: Use the hardware-qualified CLG400 ZynqSDR for the first receiver integration

**Status:** Accepted
**Date:** 2026-08-27
**Deciders:** Project maintainer

## Context

The algorithmic HDL was measured out of context for `xc7z020clg484-1`, described
as a ZC702 plus FMCOMMS2. The available hardware-qualified SDR path in the
companion `zynq-sdr-course` project uses the actual board part
`xc7z020clg400-2`, an imported AD9361 vendor snapshot, and a verified boot and
RF workflow. Package pins, speed grade, PS configuration and bitstreams are not
interchangeable between these targets.

The first hardware milestone needs the shortest evidence-backed route from the
working LoRa RTL to real AD936x samples. It must not introduce a runtime
dependency on a sibling checkout or copy the course's educational CSS detector.

## Decision

The first board-integrated LoRa receiver targets the hardware-qualified CLG400
ZynqSDR (`xc7z020clg400-2`). The course's vendor snapshot and its overlay,
clock-domain and clean-boot methods are the board-support reference. The LoRa
repository remains authoritative for every LoRa DSP core, timestamp contract,
test vector and measurement result.

The portable receiver RTL remains part-agnostic. ZC702/`xc7z020clg484-1` stays
available as a secondary OOC comparison target, but its existing synthesis and
post-route results are not board evidence for the CLG400 target.

Before board assembly, the CLG400 integration flow will consume a pinned,
checksummed board-support snapshot or a minimal extracted adapter. It will not
depend on an adjacent `zynq-sdr-course` working tree.

## Options Considered

### Option A: CLG400 hardware-qualified ZynqSDR

| Dimension | Assessment |
|---|---|
| Integration risk | Medium; LoRa overlay is new, board shell is measured |
| Reproduction | Good after pinning the board-support snapshot |
| Hardware evidence | Strong: clean boot, routed timing and two-board RF history |
| Portability | Preserved below the board adapter |

**Pros:** Reuses the only locally demonstrated AD9361 boot/RF path and its CDC
lessons. Provides the shortest route to an on-air LoRa timestamp.

**Cons:** Existing CLG484 OOC reports must be repeated for CLG400. The course
dual-modem overlay cannot be retained because it consumes almost all DSP48s.

### Option B: ZC702 plus FMCOMMS2

| Dimension | Assessment |
|---|---|
| Integration risk | High until the exact board and boot path are qualified |
| Reproduction | Algorithmic OOC flow exists; complete board flow does not |
| Hardware evidence | No LoRa or board-top evidence in this repository |
| Portability | Native match to the existing CLG484 reports |

**Pros:** Matches the part used by the current OOC evidence and the upstream
ADI ZC702 naming.

**Cons:** Does not reuse the hardware-qualified CLG400 bitstream, constraints
or pinout. It would start a second board bring-up before proving the receiver.

## Trade-off Analysis

The first milestone optimizes for measured end-to-end progress, not for keeping
the original OOC part name. Keeping the receiver RTL portable makes the choice
reversible, while choosing the known CLG400 platform removes the largest board
bring-up uncertainty. The cost is an honest rerun of synthesis and timing for
the actual device.

## Consequences

- CLG400 timing, utilization and power reports become the acceptance evidence
  for the first hardware receiver.
- Existing CLG484 reports remain useful algorithm-core comparisons and are
  explicitly labelled as such.
- The LoRa overlay replaces, rather than extends, the course QPSK modem overlay.
- Sample/DSP and PS/AXI clock domains require an explicit asynchronous boundary.
- A later ZC702 port needs only a new board adapter and constraints, not a new
  LoRa receiver architecture.

## Action Items

1. [x] Keep the complete LoRa PHY and educational CSS implementations separate.
2. [x] Compose the packet-rate matched-filter ToA path in portable RTL.
3. [x] Repeat full receiver out-of-context synthesis for `xc7z020clg400-2`;
   board implementation remains part of item 4.
4. [x] Extract the hardware-qualified CLG400 shell as a read-only input and
   compose the LoRa RX1/gpreg overlay in a separate generated project.
5. [ ] Validate clean boot, AD9361 sample activity and AXI timestamp reads.
