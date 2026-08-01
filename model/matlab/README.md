# MATLAB floating-point model

This directory is the authoritative algorithm layer. Current scope is a compact
CSS symbol model that fixes chirp, cyclic-shift, FFT-bin, CFO, and sample-shape
conventions before the full LoRa PHY is implemented.

Run all tests from MATLAB:

```matlab
cd model/matlab
results = run_tests;
assertSuccess(results);
```

Package functions use column vectors and normalized CFO in cycles per sample.
For physical rate `Fs`, convert with `cfoNormalized = cfoHz / Fs`.

Planned subpackages will separate waveform/packet coding, synchronization,
channel impairments, metrics, and golden-vector export. Avoid HDL-specific
optimizations here; those belong in the Simulink stage.
