# LoRa AXI4-Lite control/status register map

`fpga/wrappers/lora_axi_lite_status.v` is the first software-facing control/status
block for the receiver integration layer. It is intentionally vendor-independent
RTL and can be connected to a Zynq AXI4-Lite interconnect without Xilinx IP inside
the block itself.

The register bank consumes the atomic metadata event produced by
`lora_timestamp_metadata_join.v`. A complete timestamp is captured as one event:

- 64-bit coarse sample count;
- signed 32-bit fractional ToA in Q12 units (1/4096 sample);
- one sequence increment per event.

## Register map

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x00` | `CONTROL` | RW | bit 0: `receiver_enable`; bit 1: write-one-to-clear status flags |
| `0x04` | `STATUS` | RO | bit 0: snapshot valid; bit 1: metadata overflow sticky; bit 2: receiver enabled |
| `0x08` | `SEQUENCE` | RO | increments for every accepted metadata event |
| `0x0c` | `COARSE_LO` | RO | coarse timestamp bits `[31:0]` |
| `0x10` | `COARSE_HI` | RO | coarse timestamp bits `[63:32]` |
| `0x14` | `FRACTION` | RO | signed fractional ToA Q12, raw 32-bit two's-complement value |
| `0x18` | `VERSION` | RO | register-map version `0x0001_0000` |

Unmapped reads return zero. AXI read/write responses are `OKAY`.

## Snapshot semantics

A `metadata_valid` pulse copies the coarse and fractional fields into stable
snapshot registers and increments `SEQUENCE`. The snapshot remains unchanged
until the next complete metadata event.

Software that needs a strictly consistent timestamp while metadata may continue
arriving can use this read pattern:

1. read `SEQUENCE` as `seq_before`;
2. read `COARSE_LO`, `COARSE_HI`, and `FRACTION`;
3. read `SEQUENCE` again as `seq_after`;
4. accept the sample only when `seq_before == seq_after`; otherwise repeat.

This avoids torn software observations without stalling the hardware metadata
producer.

## Sticky status

`STATUS.snapshot_valid` becomes one after the first metadata event.
`STATUS.metadata_overflow_sticky` records any pulse from the upstream metadata
joiner and remains set until software clears status.

Write `CONTROL.bit1 = 1` to clear both sticky status bits. The timestamp snapshot
and sequence counter are deliberately preserved. If a new metadata/overflow event
arrives in the same clock cycle as the clear operation, the new event wins and is
not lost.

`CONTROL.bit0` is a persistent `receiver_enable` output intended for the future
receiver-level wrapper. Clearing status while keeping the receiver enabled is
therefore normally done by writing `0x00000003`, followed later by
`0x00000001` if no additional clear is required.

## Verification

`fpga/tb/tb_lora_axi_lite_status.sv` is a self-checking Icarus-compatible
SystemVerilog testbench. It covers:

- reset values and register-map version;
- receiver enable control;
- atomic coarse/fractional snapshot reads;
- sequence-counter increments;
- sticky overflow behavior;
- write-one-to-clear semantics;
- preservation of snapshot data across status clear;
- AXI4-Lite write address/data channels arriving in different cycles;
- unmapped reads.

The main GitHub Actions CI compiles and runs this testbench together with the
existing timestamp metadata joiner regression.

## Integration boundary

This block does **not** complete milestone M3 by itself. The remaining integration
work still includes the board-facing receiver streaming wrapper, clock/reset and
CDC policy, connection to actual coarse-counter/fractional-ToA sources, regenerated
namespaced HDL Coder outputs, and wrapper-level simulation of the complete receiver
path before Zynq/AD936x hardware integration.
