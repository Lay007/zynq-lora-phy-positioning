# MATLAB floating-point model

This directory is the authoritative algorithm layer. It contains the CSS
waveform model, complete LoRa packet TX/RX, hard and soft coding chains,
continuous-IQ acquisition, fractional ToA, calibrated TDoA observations, and
weighted 2D multilateration.

Run all tests from MATLAB:

```matlab
cd model/matlab
results = run_tests;
assertSuccess(results);
```

Generate acquisition, uncoded CSS, and coded packet figures plus CSV tables:

```matlab
outputs = run_visualizations;
```

Reproduce the complete M1 packet and positioning acceptance campaign:

```matlab
addpath examples
report = run_m1_acceptance;
```

The symbol-demodulation figure can also be generated independently without
regenerating the Monte Carlo plots:

```matlab
addpath examples
[result, figureHandle] = plot_symbol_demodulation;
```

Open the visual IQ packet inspector:

```matlab
addpath apps
app = lora_phy_inspector;
```

It reads headerless RTL-SDR CU8 and Pluto/GNU Radio CF32 files and estimates the
strongest CSS burst's BW, SF, carrier offset, symbol duration, SNR, DC/IQ
impairments, and dechirped FFT bins. Generate a deterministic input with
`generate_inspector_demo_capture` from the `examples` directory. Full usage and
measurement limits are documented in
[`docs/lora-phy-inspector.md`](../../docs/lora-phy-inspector.md).

Package functions use column vectors and normalized CFO in cycles per sample.
For physical rate `Fs`, convert with `cfoNormalized = cfoHz / Fs`.

`lora_phy.apply_channel_impairments` provides a deterministic, toolbox-free
channel/front-end model for offline verification. It combines fractional
delay, multipath, sample-rate offset (SFO), carrier offset, I/Q gain and phase
imbalance, DC offset, and seeded complex AWGN:

```matlab
rx = lora_phy.apply_channel_impairments(tx, Fs, ...
    FractionalDelaySamples=2.25, SampleRateOffsetPpm=20, ...
    MultipathDelaysSamples=[0; 3.5], MultipathGains=[1; 0.3j], ...
    FrequencyOffsetHz=1800, IqGainImbalanceDb=0.5, ...
    IqPhaseImbalanceDegrees=2, SnrDb=-8, RandomSeed=42);
```

Positive SFO advances through the nominal transmit samples faster; positive
fractional delay moves the received waveform later. The output length is
always equal to the input length, with zeros outside the interpolated range.

Export the committed deterministic packet vector after changing a coding block:

```matlab
vector = export_golden_vectors;
```

Avoid HDL-specific optimizations here; those belong in the Simulink stage.

## Current frame receiver

`build_css_frame` creates a research acquisition frame with eight upchirps, two
downchirps, and uncoded payload symbols. `receive_css_frame` searches all
integer-sample start candidates, estimates CFO from the first upchirp, and
demodulates the requested payload length. This deliberately tests acquisition
independently of the packet-coding path and exact LoRa sync-word waveform.

## Standard on-air packet receiver

`encode_packet` produces CSS symbol indices and exposes every intermediate
vector. `decode_packet` accepts hard symbol decisions. `receive_lora_packet`
adds acquisition of a standard LoRa preamble, two sync-word symbols, the
2.25-downchirp SFD, CFO correction, timing search, explicit-header decoding,
deinterleaving, FEC, dewhitening, and payload CRC validation. SX126x SF5/SF6
explicit-header framing and inverted IQ are supported.

Decode and visualize the committed Heltec/SX1262 reference capture:

```matlab
d = "../../captures/reference/2026-08-03-heltec-v43-zynqsdr-mode-sweep";
[iq, ~] = lora_phy.load_iq_capture(fullfile(d, "sf7-bw125.cf32"), "cf32");
rx = lora_phy.receive_lora_packet(iq, 1e6, 125e3, 7, ...
    PreambleSymbols=12, SyncWord=hex2dec("12"), ...
    ExpectedCarrierOffsetHz=-250e3);
lora_phy.visualize_lora_packet(iq, 1e6, rx);
```

Run the entire hardware matrix with `decode_reference_sweep` from `examples`.
For every packet plus BER/PER counters, run:

```matlab
addpath examples
report = evaluate_reference_sweep(d, OutputDirectory=d);
```

`receive_lora_packets` enumerates energy-separated transmissions in time
order. Each packet exposes hard decisions, per-bin FFT metrics, max-log bit
LLRs, hard and soft FEC results, and the selected CRC-valid decode. The
reference-sweep evaluator rebuilds the deterministic firmware payload from the
TX log and reports acquisition, header, CRC, pre-FEC BER, payload BER, and PER
separately.

`build_lora_packet` and `build_lora_stream` generate standard complete packets
inside continuous IQ. `receive_lora_stream` fuses energy and chirp-sequence
candidates, validates sync and SFD transitions, and passes explicit or implicit
header configuration to the packet decoder. `evaluate_lora_stream` pairs time
truth and candidates without removing misses, false alarms, duplicates, or CRC
failures from the denominators. `simulate_lora_stream_performance` supplies
reproducible acquisition-inclusive BER/PER evidence.

`fft_correlator_metrics` is the selected coherent symbol-demodulation
candidate. For `M=N·L`, it performs an `M`-point FFT, multiplies by the
conjugated reference spectrum, aliases frequency bins spaced by `N`, and
performs an `N`-point forward FFT. It is numerically equivalent to the exact
matched-filter bank without a full `M`-point IFFT.

The on-air packet receiver learns a phase-aligned reference from the repeated
preamble and keeps the legacy polyphase path as a packet-level guard. Joint
timing/CFO resolution from the upchirp/downchirp pair removed the earlier
ambiguity: all 130 committed SX1262 packets now select the FFT correlator and
decode exactly; none require fallback. This supersedes the earlier 118/130
nominal result and the 56/74 hybrid split.

`tdoa_from_toas` subtracts fixed per-channel delays before differencing against
receiver 1. `predict_tdoa` and `solve_tdoa` implement the forward model and a
weighted Gauss-Newton multilateration solver with residual, covariance, and
geometry-condition diagnostics. `simulate_tdoa_accuracy` provides seeded
position-error Monte Carlo results.

## BER definitions

`simulate_uncoded_ber` compares natural binary labels of transmitted and
detected CSS indices in complex AWGN. Its fifth argument selects
`"single-phase"`, `"polyphase"`, `"fft-correlator"`, or `"matched-filter"`;
logical false/true remain aliases for the first two modes. The matched filter coherently
correlates every complex sample with the complete cyclic-shift waveform bank
and remains the independent floating-point AWGN reference. The FFT correlator
is the algebraically equivalent HDL-oriented decomposition.
The table contains BER/SER, raw counts, denominators, energy-axis conversions,
and 95% Wilson intervals.

`simulate_coded_ber` additionally reports pre-FEC BER, hard and soft payload
BER/PER, soft-recovered packets, header/CRC failures, undetected errors, and
confidence intervals. Failed packet decodes count all payload bits as errors.

Generate the current three-figure campaign with:

```matlab
addpath examples
campaign = plot_ber_campaign;
```
