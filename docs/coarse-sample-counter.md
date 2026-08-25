# PL coarse sample counter

The receiver control path owns a 64-bit programmable-logic sample timebase in
`fpga/wrappers/lora_sample_counter_capture.v`.

## Counter semantics

- `sample_valid` qualifies one accepted complex input sample.
- The live counter increments once for each rising clock edge with
  `sample_valid=1`; idle clock cycles do not advance time.
- `coarse_capture` snapshots the number of accepted samples observed **before**
  the current rising edge.
- If `sample_valid` and `coarse_capture` are asserted on the same edge, the
  captured value is the pre-increment count and the live counter advances by
  one after the capture.
- `capture_valid` is a one-clock pulse associated with each coarse snapshot.
- Reset is synchronous and active-low, matching the current control/metadata
  subsystem convention.
- The production counter width is 64 bits and wraparound is modulo `2^64`.
  The RTL parameterizes the width so the regression can exercise wraparound
  with a short simulation.

The sample counter is independent of the AXI `receiver_enable` control bit.
Stopping algorithmic processing must not stop the timestamp timebase once the
board-facing accepted-sample stream is connected.

## Clock-domain contract

The current receiver control wrapper is intentionally single-domain:
`sample_valid`, `coarse_capture`, the fractional-ToA fragment, the metadata
joiner and AXI-Lite all use `s_axi_aclk`. This is a verification boundary, not
a claim that the final AD936x datapath will use the same clock. If the board
sample stream or generated detector runs in another domain, an explicit CDC
stage is required before this control/metadata subsystem.

## Detector latency

The captured count identifies the sample-time state at the `coarse_capture`
event. It does not silently compensate detector pipeline latency. When the real
packet detector is connected, its fixed latency must be measured/documented and
either:

1. the capture event must be aligned back to the intended packet reference
   sample; or
2. the known latency must be subtracted as an explicit calibrated offset.

Keeping that correction explicit avoids mixing algorithm latency with the PL
sample timebase definition.

## Verification

`fpga/tb/tb_lora_sample_counter_capture.sv` checks reset, accepted-sample
counting, idle cycles, one-cycle capture-valid timing, simultaneous
sample/capture pre-increment semantics and modulo wraparound.

`fpga/tb/tb_lora_receiver_control_wrapper.sv` verifies the integrated path:

`sample_valid -> PL counter -> coarse_capture -> metadata joiner -> AXI-Lite`.

Issue #16 remains the acceptance tracker until the real packet-detection event
is connected to `coarse_capture`; the current regression proves the counter and
control-path semantics, not board-level packet timing.
