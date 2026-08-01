# MATLAB floating-point model

This directory is the authoritative algorithm layer. Current scope fixes chirp,
cyclic-shift, FFT-bin, CFO, sample-shape, integer timing, and uncoded BER/SER
conventions before the full LoRa PHY is implemented.

Run all tests from MATLAB:

```matlab
cd model/matlab
results = run_tests;
assertSuccess(results);
```

Generate both figures and the BER/SER CSV table:

```matlab
outputs = run_visualizations;
```

Package functions use column vectors and normalized CFO in cycles per sample.
For physical rate `Fs`, convert with `cfoNormalized = cfoHz / Fs`.

Planned subpackages will separate waveform/packet coding, synchronization,
channel impairments, metrics, and golden-vector export. Avoid HDL-specific
optimizations here; those belong in the Simulink stage.

## Current frame receiver

`build_css_frame` creates a research acquisition frame with eight upchirps, two
downchirps, and uncoded payload symbols. `receive_css_frame` searches all
integer-sample start candidates, estimates CFO from the first upchirp, and
demodulates the requested payload length. This deliberately tests acquisition
before whitening, FEC, CRC, and the exact LoRa sync/header format are introduced.

## Current BER definition

`simulate_uncoded_ber` compares the natural binary labels of transmitted and
detected CSS symbol indices in complex AWGN. It assumes known symbol timing and
does not include preamble failures, coding, or packet rejection. The returned
table contains BER, SER, raw error counts, and trial counts.
