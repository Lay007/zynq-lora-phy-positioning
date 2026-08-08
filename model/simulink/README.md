# Simulink implementation

This is stage two, after the MATLAB floating-point behavior is stable. No `.slx`
is committed: every model is rebuilt from a generation script, so deleting the
`.slx` and regenerating it is the normal workflow rather than a recovery step.

The measured toolchain, the frozen M2 interface contract, and the stage-vector
format are in
[`docs/simulink-m2-interfaces.md`](../../docs/simulink-m2-interfaces.md).

Verify the products and licenses M2 depends on:

```matlab
cd model/simulink
report = report_toolchain;
```

Presence in `ver` is not accepted as proof; every feature is checked out. Note
that HDL Coder is licensed as `Simulink_HDL_Coder` and HDL Verifier as
`eda_simulator_link`, so checking `HDL_Coder` or `HDL_Verifier` wrongly reports
them as absent.

## First DUT

The initial HDL-oriented subsystem will implement:

```text
complex sample stream
    → N·L streaming FFT
    → reference-spectrum multiply
    → sum L frequency partitions
    → N-point FFT
    → magnitude/peak detector
    → symbol index + valid
```

The model must define:

- sample and clock rates;
- `valid`, framing, and backpressure behavior;
- fixed-point types at every boundary;
- rounding, saturation, and overflow policy;
- pipeline latency and reset behavior;
- tunable versus compile-time LoRa parameters;
- comparison points against MATLAB golden vectors.

The first DUT implements only the coherent FFT-correlator path. Adaptive
preamble-reference estimation, the legacy polyphase fallback, packet decoding,
and CRC-based path selection remain outside the DUT until their resource and
mismatch trade-offs are measured.

## HDL generation rules

- Use a named DUT subsystem as the only HDL Coder target.
- Keep test benches and visualization outside the DUT.
- Version the model, initialization script, HDL configuration, and vector-export
  script together.
- Generate Verilog, not VHDL, for the first ZynqSDR integration.
- Run fixed-point comparison and HDL cosimulation before Vivado synthesis.
- Never hand-edit generated algorithmic Verilog.
