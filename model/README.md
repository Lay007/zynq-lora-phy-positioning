# Modeling flow

The project uses MATLAB and Simulink as the authoritative algorithm-to-HDL flow.
The layers have different responsibilities and must not be collapsed too early.

## 1. MATLAB floating point

MATLAB defines the expected numerical behavior without HDL architecture or word
length constraints. It contains waveform generation, channel impairments,
synchronization, PHY and ToA/TDoA algorithms, metrics, plots, and deterministic
golden-vector generation.

An algorithm leaves this stage only when its conventions, tests, tolerances,
failure cases, and expected outputs are explicit.

## 2. Simulink

Simulink converts the verified algorithm into a streaming architecture. This is
where sample rates, valid/control timing, buffers, state, latency, rounding,
saturation, and fixed-point types become explicit.

The model must continuously compare selected signals with MATLAB golden vectors.
The Simulink model—not generated HDL—is the implementation source of truth.

## 3. Generated Verilog

HDL Coder generates Verilog from the reviewed DUT subsystem. Generation scripts
and configuration are versioned. HDL cosimulation checks cycle-level output
against Simulink/MATLAB vectors before Vivado integration.

Only real-time streaming PHY and ToA blocks are HDL targets. Cross-station event
association, calibration, and TDoA multilateration stay in host/PS software.

Generated algorithmic HDL is not edited by hand. Necessary behavioral changes
go back into MATLAB requirements and Simulink.

## 4. ZynqSDR integration

Vivado integrates generated IP with the AD936x sample path, clocks, resets, AXI
control/data transport, timestamping, and board constraints. Hardware captures
retain links to the MATLAB vector revision, Simulink model revision, HDL
generation configuration, and bitstream checksum.
