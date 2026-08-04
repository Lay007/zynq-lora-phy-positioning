# MATLAB floating-point model

This directory is the authoritative algorithm layer. It contains the CSS
waveform model and a hard-decision LoRa packet-coding chain: explicit header,
payload CRC, whitening, Hamming coding, diagonal interleaving, Gray mapping,
and the inverse receiver path.

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

## BER definitions

`simulate_uncoded_ber` compares the natural binary labels of transmitted and
detected CSS symbol indices in complex AWGN. It assumes known symbol timing and
does not include preamble failures, coding, or packet rejection. The returned
table contains BER, SER, raw error counts, and trial counts.

`simulate_coded_ber` additionally reports pre-FEC BER, recovered-payload BER,
PER, header failures, and CRC failures. Failed packet decodes count all payload
bits as errors in its conservative payload-BER metric.
