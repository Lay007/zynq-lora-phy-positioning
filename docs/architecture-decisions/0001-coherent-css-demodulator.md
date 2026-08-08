# ADR-0001: Coherent FFT correlator with packet-level fallback

**Status:** Accepted
**Date:** 2026-08-08

## Context

The original oversampled receiver dechirped each of `L=Fs/BW` sample phases,
ran `N=2^SF` FFTs, and summed their powers. At `L=8` it lost `5.33 dB` at BER
`1e-2` and `6.03 dB` at BER `1e-3` relative to the exact matched filter.
Directly instantiating `N` time-domain correlators is not an attractive HDL
boundary.

A nominal coherent matched filter closes the AWGN gap but decoded only 118 of
130 committed SX1262→ZynqSDR transmissions. The real RF/baseband path adds
waveform, filtering, timing, and residual-frequency mismatch that the legacy
power sum tolerates better.

## Decision

The first Simulink/HDL candidate is an exact FFT correlator. For `M=N·L` it
uses:

```text
M-point FFT
  → multiply by conjugated reference spectrum
  → sum frequency bins m+rN for r=0…L−1
  → N-point forward FFT
  → magnitude and peak search
```

This produces the matched-filter correlations at lags `−kL` and is
numerically equivalent to the independent full-IFFT reference.

The MATLAB packet receiver additionally estimates a phase-aligned reference
from repeated preamble upchirps and evaluates both the FFT correlator and the
legacy polyphase path for every timing hypothesis. Header and CRC evidence
select the packet result. Adaptive estimation and fallback remain outside the
first HDL DUT.

## Options considered

| Option | AWGN performance | Real IQ | HDL cost | Decision |
|---|---|---|---|---|
| First decimation phase | Loses oversampling gain | Simple | Low | Rejected |
| Sum polyphase FFT powers | 5–6 dB from reference at `L=8` | 130/130 | Medium | Retained as fallback |
| Time-domain template bank | Optimal | Mismatch-sensitive | Very high | Reference only |
| FFT correlator | Optimal and exact | 118/130 nominal; hybrid 130/130 | To be measured | First DUT |

## Consequences

- Floating-point AWGN loss to the exact reference is `0 dB`.
- The DUT needs whole-symbol framing, an `M`-point transform, reference ROM or
  RAM, frequency-partition accumulation, and an `N`-point transform.
- Simulink must measure whether the two FFT stages can share resources while
  satisfying one-symbol throughput.
- Real-waveform robustness cannot be inferred from AWGN alone; the committed
  IQ regression remains mandatory.
- The current packet result is 130/130: 56 packets selected the FFT correlator
  and 74 selected the polyphase fallback.

## Follow-up

1. Export stage-level complex golden vectors.
2. Define streaming order, buffering, `valid/ready`, and reset behavior.
3. Quantize reference coefficients and both FFT stages.
4. Measure latency, resources, and the cost of retaining fallback metrics.
5. Add CFO/SFO/timing/multipath sweeps before removing the fallback.
