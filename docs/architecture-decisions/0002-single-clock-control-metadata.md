# ADR 0002: Keep the first receiver control/metadata wrapper single-clock

- Status: Accepted
- Date: 2026-08-25

## Context

The LoRa receiver integration now has two independently verified primitives:

1. `lora_timestamp_metadata_join` combines coarse and fractional ToA fragments
   into one atomic metadata record.
2. `lora_axi_lite_status` exposes stable metadata snapshots and receiver status
   to the Zynq processing system through AXI4-Lite.

The eventual receiver datapath may not use the same clock as the processing
system AXI-Lite interface. In particular, an AD936x-facing sample path and
HDL-Coder-generated DSP cores may introduce a separate sample clock or derived
processing clocks.

Adding an implicit clock-domain crossing now would hide an architectural choice
before the final receiver clock plan is known.

## Decision

`lora_receiver_control_wrapper` is intentionally single-clock-domain:

- AXI4-Lite uses `s_axi_aclk`;
- `coarse_sample_count` / `coarse_valid` are synchronous to `s_axi_aclk`;
- `fractional_toa_q12` / `fractional_valid` are synchronous to `s_axi_aclk`;
- the metadata joiner and AXI register bank both run from `s_axi_aclk`;
- reset is `s_axi_aresetn` for the whole control/metadata subsystem.

No synchronizer, asynchronous FIFO, toggle bridge, or pulse stretcher is hidden
inside this wrapper.

## Consequences

### Positive

- The current RTL contract is explicit and easy to verify.
- Metadata pairing semantics are independent of any speculative CDC design.
- AXI-visible sequence/snapshot behavior can be tested deterministically.
- Future CDC logic can be reviewed and tested as a separate integration block.

### Constraint

A future receiver top **must not** connect metadata pulses generated in another
clock domain directly to this wrapper. If the DSP/sample clock differs from
`s_axi_aclk`, an explicit CDC boundary is required first.

The preferred CDC location will be selected after the board-facing receiver
clock plan is fixed. Candidate approaches include transferring the already
joined metadata record through a small asynchronous FIFO or using a request /
acknowledge snapshot bridge. A single-bit two-flop synchronizer alone is not
sufficient for a coherent multiword timestamp record.

## Verification

`fpga/tb/tb_lora_receiver_control_wrapper.sv` verifies the current same-clock
contract end-to-end, including reset of a partial metadata record. CDC behavior
is deliberately outside the scope of that test.
