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

## Packet model boundary

`encode_packet` produces CSS symbol indices and exposes every intermediate
vector. `decode_packet` accepts hard symbol decisions. Standard LoRa preamble,
sync-word waveform, soft decoding, and SX1262 IQ-capture interoperability are
the next compatibility boundary; the current coded BER uses known timing.

## BER definitions

`simulate_uncoded_ber` compares the natural binary labels of transmitted and
detected CSS symbol indices in complex AWGN. It assumes known symbol timing and
does not include preamble failures, coding, or packet rejection. The returned
table contains BER, SER, raw error counts, and trial counts.

`simulate_coded_ber` additionally reports pre-FEC BER, recovered-payload BER,
PER, header failures, and CRC failures. Failed packet decodes count all payload
bits as errors in its conservative payload-BER metric.
