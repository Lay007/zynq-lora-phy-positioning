# Roadmap

The roadmap uses measurable gates. Dates are intentionally omitted: a stage is
complete only when its acceptance evidence is committed or linked.

## M0 — Reproducible repository

- [x] Packageable Python project and automated tests.
- [x] CSS modulation/demodulation, channel impairments, ToA, and TDoA baseline.
- [x] Architecture, bench requirements, and experiment templates.
- [ ] Add a small, redistributable SX1262 IQ capture with provenance.

Acceptance: a clean checkout installs and all tests pass.

## M1 — Offline LoRa symbol receiver

- [ ] Capture Heltec SX1262 packets at BW 125 kHz and SF7.
- [ ] Detect repeated upchirps without a priori packet start.
- [ ] Estimate and compensate carrier frequency offset.
- [ ] Detect the sync-word/downchirp transition and symbol boundary.
- [ ] Recover all payload symbol indices and compare with a known transmission.

Acceptance: deterministic processing of at least 1,000 captures with a recorded
detection rate, symbol error rate, CFO error, and false-alarm rate.

## M2 — Complete software PHY

- [ ] Explicit and implicit header modes.
- [ ] Whitening, interleaving, Hamming coding, and CRC.
- [ ] SF7–SF12 and BW 125/250/500 kHz.
- [ ] CFO/SFO tracking and configurable low-data-rate optimization.
- [ ] Packet generation compatible with SX1262.

Acceptance: bidirectional interoperability with Heltec, plus packet-error-rate
curves versus SNR and input power for each supported configuration.

## M3 — PL receiver datapath

- [ ] Fixed-point model with documented scaling and saturation.
- [ ] Streaming dechirp, FFT, peak interpolation, and timestamp unit.
- [ ] Assertions for AXI-Stream framing and counter behavior.
- [ ] RTL or HLS regression against shared golden vectors.
- [ ] Synthesis, timing, resource, and power reports.

Acceptance: PL reports the same symbols and bounded ToA error as the reference
model for the regression corpus, with no AXI protocol violations.

## M4 — Single-receiver ToA

- [ ] Coarse sample counter captured in PL.
- [ ] Fractional ToA estimator and confidence metric.
- [ ] Cable-loopback delay calibration.
- [ ] Repeatability study versus SNR, SF, BW, AGC mode, and input level.

Acceptance: published bias, standard deviation, and outlier rate over a defined
input range; all raw-data checksums and configurations are retained.

## M5 — Three-receiver synchronized TDoA

- [ ] Verify external reference and synchronization access on every ZynqSDR.
- [ ] Distribute a common clock and epoch pulse directly to PL.
- [ ] Measure channel-to-channel fixed delay and drift.
- [ ] Associate packets across three stations and solve calibrated 2D TDoA.
- [ ] Compare estimated positions against surveyed ground truth.

Acceptance: cable test first, then indoor/field results with horizontal error
CDF, geometry, calibration revision, and uncertainty budget.

## M6 — Research extensions

- [ ] Adaptive chirp/CSS waveforms for joint communication and positioning.
- [ ] TDoA/FDoA fusion and multipath-robust estimators.
- [ ] Compare manual RTL and HLS for selected kernels.
- [ ] Publish a repeatable benchmark and technical report.

## Core metrics

| Area | Metrics |
|---|---|
| Link | sensitivity, PER vs SNR/input power, CFO/SFO tolerance |
| Synchronization | detection probability, false alarms, timing bias/jitter |
| Positioning | TDoA residual, horizontal error CDF, outlier rate |
| FPGA | LUT/FF/BRAM/DSP, Fmax, latency, throughput, power |
| Compatibility | SF/BW/CR modes and SX1262 interoperability |
