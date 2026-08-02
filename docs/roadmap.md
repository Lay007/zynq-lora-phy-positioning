# Roadmap

The roadmap uses measurable gates. Dates are intentionally omitted: a stage is
complete only when its acceptance evidence is committed or linked.

## M0 — Reproducible repository

- [x] MATLAB project layout and automated floating-point CSS tests.
- [x] Auxiliary packageable Python checks for CSS, ToA, and TDoA.
- [x] Architecture, bench requirements, and experiment templates.
- [x] Add a redistributable LR1121 IQ reference capture with provenance via Git LFS.
- [x] Record and checksum a 27-mode LR1121-to-ZynqSDR IQ sweep covering
  SF, BW, CR, power, payload, preamble, CRC, sync word, and IQ polarity.
- [x] Build and safely initialize stopped-by-default Heltec V4/SX1262 firmware;
  RF validation remains gated on PCB-revision and antenna confirmation.

Acceptance: a clean checkout runs both MATLAB and auxiliary Python tests.

## M1 — MATLAB floating-point PHY and positioning

- [x] CSS upchirp and downchirp generation.
- [x] Symbol modulation, dechirp/FFT demodulation, AWGN, and CFO baseline.
- [x] Hard-decision LoRa packet encode/decode: explicit header, whitening,
  interleaving, Hamming code, CRC, and Gray/CSS symbol mapping.
- [x] Detect the research 8-up/2-down preamble without a priori frame start.
- [x] Estimate and compensate carrier frequency offset on synthetic frames.
- [x] Produce reproducible uncoded BER/SER versus sample SNR results.
- [ ] Implement the standard LoRa sync-word/downchirp transition and packet
  boundary conventions.
- [ ] Model SFO, timing offset, multipath, and AD936x-relevant impairments.
- [ ] Implement coarse/fractional ToA estimators and characterize bias/jitter.
- [ ] Implement calibrated TDoA observations and 2D multilateration.
- [x] Generate a versioned SF7/CR1 golden packet vector with intermediate
  values for the current HDL-bound bit-processing blocks.
- [ ] Capture Heltec SX1262 packets at BW 125 kHz and SF7 and recover them with
  the MATLAB model.

Acceptance: deterministic simulation and processing of at least 1,000 captures
with recorded detection/symbol/CFO metrics plus ToA bias/jitter and TDoA position
error for defined geometry and impairments.

## M2 — Simulink executable architecture

- [ ] Reproduce the verified MATLAB algorithm in a sample-streaming model.
- [ ] Define frame/control signals, valid/ready behavior, and rate changes.
- [ ] Convert arithmetic to explicit fixed-point types with saturation/rounding.
- [ ] Compare every stage against MATLAB golden vectors.
- [ ] Establish latency, throughput, and reset behavior.
- [ ] Keep TDoA association/multilateration outside the HDL DUT and verify its
  timestamp/metadata interface.

Acceptance: Simulink matches MATLAB within documented tolerances for nominal,
boundary, and impairment regressions and is accepted by HDL Coder checks.

## M3 — HDL Coder Verilog generation

- [ ] Generate Verilog for dechirp, FFT, peak detection, and ToA blocks from
  Simulink.
- [ ] Run HDL cosimulation against the same golden vectors.
- [ ] Add generated-IP packaging and reproducible generation scripts.
- [ ] Integrate generated cores with hand-written clock/reset/AXI wrappers.
- [ ] Synthesis, timing, resource, and power reports.

Acceptance: regenerated Verilog is reproducible, passes cosimulation, meets
timing, and reports the same symbols as MATLAB/Simulink for the regression set.

## M4 — ZynqSDR symbol receiver

- [ ] Integrate the generated core in Vivado and connect the AD936x sample path.
- [ ] Verify Heltec-to-ZynqSDR symbol recovery at BW 125 kHz and SF7.
- [ ] Extend to the complete packet PHY and bidirectional interoperability.
- [ ] Measure PER versus SNR/input power and CFO/SFO tolerance.

Acceptance: at least 1,000 hardware packets with recorded symbol/PER metrics and
matching internal MATLAB/Simulink/Verilog test points.

## M5 — Single-receiver ToA

- [ ] Coarse sample counter captured in PL.
- [ ] Fractional ToA estimator and confidence metric.
- [ ] Cable-loopback delay calibration.
- [ ] Repeatability study versus SNR, SF, BW, AGC mode, and input level.

Acceptance: published bias, standard deviation, and outlier rate over a defined
input range; all raw-data checksums and configurations are retained.

## M6 — Three-receiver synchronized TDoA

- [ ] Verify external reference and synchronization access on every ZynqSDR.
- [ ] Distribute a common clock and epoch pulse directly to PL.
- [ ] Measure channel-to-channel fixed delay and drift.
- [ ] Associate packets across three stations and solve calibrated 2D TDoA.
- [ ] Compare estimated positions against surveyed ground truth.

Acceptance: cable test first, then indoor/field results with horizontal error
CDF, geometry, calibration revision, and uncertainty budget.

## M7 — Research extensions

- [ ] Adaptive chirp/CSS waveforms for joint communication and positioning.
- [ ] TDoA/FDoA fusion and multipath-robust estimators.
- [ ] Compare generated Verilog with selected manual RTL/HLS alternatives.
- [ ] Publish a repeatable benchmark and technical report.

## Core metrics

| Area | Metrics |
|---|---|
| Link | sensitivity, PER vs SNR/input power, CFO/SFO tolerance |
| Synchronization | detection probability, false alarms, timing bias/jitter |
| Positioning | TDoA residual, horizontal error CDF, outlier rate |
| FPGA | LUT/FF/BRAM/DSP, Fmax, latency, throughput, power |
| Compatibility | SF/BW/CR modes and SX1262 interoperability |
