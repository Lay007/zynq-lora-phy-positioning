# Simulink implementation

This is stage two, after the MATLAB floating-point behavior is stable. No empty
placeholder `.slx` is committed: the first model will be created with explicit
interfaces and regression vectors from MATLAB M1.

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
