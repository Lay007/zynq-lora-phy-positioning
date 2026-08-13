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
  electrically identify the connected board as V4.3 and validate the
  KCT8103L transmit-bypass path.
- [x] Record, checksum, and publish a 27-mode Heltec V4.3/SX1262-to-ZynqSDR IQ
  sweep through Git LFS.

Acceptance: a clean checkout runs both MATLAB and auxiliary Python tests.

## M1 — MATLAB floating-point PHY and positioning

- [x] CSS upchirp and downchirp generation.
- [x] Symbol modulation, dechirp/FFT demodulation, AWGN, and CFO baseline.
- [x] Hard-decision LoRa packet encode/decode: explicit header, whitening,
  interleaving, Hamming code, CRC, and Gray/CSS symbol mapping.
- [x] Detect the research 8-up/2-down preamble without a priori frame start.
- [x] Estimate and compensate carrier frequency offset on synthetic frames.
- [x] Produce reproducible uncoded BER/SER versus sample SNR results.
- [x] Implement the standard LoRa sync-word/downchirp transition and packet
  boundary conventions, including the 2.25-downchirp SFD and the SX126x
  low-spreading-factor padding.
- [x] Model SFO, timing offset, multipath, and AD936x-relevant impairments.
- [x] Implement coarse/fractional ToA estimators and characterize bias/jitter.
- [x] Implement calibrated TDoA observations and 2D multilateration.
- [x] Generate a versioned SF7/CR1 golden packet vector with intermediate
  values for the current HDL-bound bit-processing blocks.
- [x] Capture Heltec SX1262 packets at BW 125 kHz/SF7 and estimate their packet
  interval, bandwidth, SF, carrier/CFO, SNR, and preamble score in MATLAB.
- [x] Decode standard on-air SX1262 packet symbols and payload bytes with the
  MATLAB model.
- [x] Decode every energy-separated burst in one capture and pair the results
  with the transmitter log to report packet BER and PER.
- [x] Add max-log soft-decision symbol, deinterleaver, and Hamming decoding and
  record how many packets it recovers beyond hard decisions.
- [x] Build and receive complete packets in continuous configured IQ, including
  energy/chirp candidate fusion, implicit headers, ADC quantization,
  false-alarm accounting, and end-to-end BER/PER.

Acceptance: complete. The layered deterministic evidence exceeds 1,000 trials;
it includes 324 synthetic end-to-end stream packets, 130 real SX1262 packets,
500 fractional-ToA trials, and 3,000 calibrated TDoA position trials. See
[MATLAB M1 floating-point acceptance](matlab-m1-acceptance.md) for raw data,
metric definitions, and the explicit configuration-aided boundary.

## M2 — Simulink executable architecture

- [x] Reproduce the verified MATLAB algorithm in a sample-streaming model.
- [x] Define frame/control signals and flow-control behavior, with the
  no-backpressure decision backed by a measured full-rate throughput.
- [x] Convert arithmetic to explicit fixed-point types with saturation/rounding
  and sweep the word length.
- [x] Compare every stage against MATLAB golden vectors.
- [x] Establish latency and throughput.
- [x] Replay recorded SX1262 symbol windows through the fixed-point model.
- [x] Pass HDL Coder compatibility checks: `checkhdl` reports zero errors on
  the fixed-point correlator and the joint timing/CFO DUT.
- [x] Establish reset behavior: `resetIn` returns the DUT to its power-up
  state, proven by driving a second waveform after a mid-stream reset.
- [x] Model preamble and sync-word acceptance on the symbol stream, exact
  against MATLAB over 615 sequences.
- [x] Model blind packet-start detection on the free-running symbol stream,
  exact against MATLAB over 2000 symbols and all 256 sync words. No sliding
  correlation is involved: the preamble bin equals the whole-chip offset, so
  detection costs 0 multipliers and 0 RAMs.
- [x] Realign the window grid by `chipsToBoundary` and compose the correlator,
  detector, and realignment into one front-end. A packet at an unknown sample
  offset is acquired and demodulates to the same payload as an aligned one,
  verified at four offsets.
- [x] Validate the SFD downchirp pair, reusing the correlator's own reference
  ROM at a complemented address rather than adding a second table, and build
  the packet-level framing state machine with re-arming. Bit-exact against
  MATLAB over 390 symbols, 7 packets and 15 rejections.
- [ ] Build the SFD validation DUT in Simulink; only the MATLAB reference
  exists so far.
- [ ] Keep TDoA association/multilateration outside the HDL DUT and verify its
  timestamp/metadata interface. The coarse sample count and its valid flag are
  implemented and checked; the fractional ToA is not, because it needs the
  sample-rate matched filter that belongs to acquisition.

Acceptance: Simulink matches MATLAB within documented tolerances for nominal,
boundary, and impairment regressions and is accepted by HDL Coder checks.
Measurements so far are in [M2 acceptance](simulink-m2-acceptance.md); the
milestone remains open on the unchecked items above.

## M3 — HDL Coder Verilog generation

- [x] Generate Verilog for the fixed-point FFT correlator, the blind detector,
  the acquisition FSM, and the joint timing/CFO estimator, with HDL Coder
  operator counts recorded.
- [ ] Generate Verilog for the ToA block once it exists.
- [ ] Run HDL cosimulation against the same golden vectors. Blocked: no HDL
  simulator is installed.
- [x] Add a reproducible generation script (`run_hdl_generation`).
- [ ] Add generated-IP packaging.
- [ ] Integrate generated cores with hand-written clock/reset/AXI wrappers.
- [x] Out-of-context synthesis with resource and timing reports
  (`run_synthesis`, Vivado 2021.1, `xc7z020clg484-1`). An earlier entry here
  claimed Vivado was not installed on the development host; that was wrong.
- [ ] Place, route, and power reports, which need the board wrapper, clocking,
  and AXI that do not exist yet.

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
