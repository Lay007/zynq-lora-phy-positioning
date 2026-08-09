# M2 acceptance: Simulink measurements

[Русская версия](ru/simulink-m2-acceptance.md)

Measured results for the executable Simulink model. Every number here comes
from a committed script and a committed table; nothing is estimated. The
interface contract, toolchain, and vector format are in
[M2 foundations](simulink-m2-interfaces.md).

M2 is **not complete**. This document records what has been measured and names
what still blocks acceptance.

## Reproducing

```matlab
cd model/simulink
results = run_simulink_regression;                       % toolchain, double, joint
results = run_simulink_regression(Suites=["fixed" "real"]);   % long campaigns
```

The command raises an error on any mismatch, so

```bash
matlab -batch "cd model/simulink; run_simulink_regression"
```

returns a nonzero exit code when Simulink and MATLAB disagree. This was
verified by forcing the tolerance to `1e-20`: the run exits with code 1.

Deleting `model/simulink/generated/` before the run is safe and is part of the
check — every model is rebuilt from its generation script.

## Stage-by-stage double equivalence

The committed golden `input` stage is the stimulus, so only the Simulink path
is under test. All 15 acceptance cases pass.

| Result | Value |
|---|---|
| Cases | 15 / 15 |
| Symbol decisions identical to MATLAB | 15 / 15 |
| Worst relative RMS error, any stage | `8.334e-16` |
| Worst confidence absolute error | `1.887e-15` |
| Reference ROM vs golden `conjReferenceSpectrum` | `0` (bit-identical) |
| Acceptance tolerance applied | relative RMS ≤ `1e-12` |

Per comparison point, worst case over all 15 cases:

| Stage | Elements compared | Max absolute error | Worst relative RMS |
|---|---:|---:|---:|
| `fftM` | 16384 | `1.400e-13` | `4.051e-16` |
| `product` | 16384 | `1.150e-11` | `4.110e-16` |
| `partition` | 7904 | `1.140e-11` | `4.110e-16` |
| `fftN` | 7904 | `2.572e-12` | `8.334e-16` |
| `magnitudeSquared` | 7904 | `5.821e-10` | `5.786e-16` |

Absolute error grows with stage scale and is meaningless on its own: `fftM`
values reach `M` times the input amplitude, and `magnitudeSquared` is a square.
Relative RMS stays at the `1e-16` level everywhere, which is double-precision
rounding, not an algorithmic difference.

Raw tables:

- [`simulink-m2-stage-comparison.csv`](data/simulink-m2-stage-comparison.csv) —
  one row per case and stage.
- [`simulink-m2-case-summary.csv`](data/simulink-m2-case-summary.csv) — one row
  per case with decisions, confidence, latency, and throughput.

## Latency and throughput

Latency is counted from the **last input sample of a symbol window**, which is
the earliest instant at which that symbol could possibly be decided. All values
are in sample clocks; the DUT runs one sample per clock.

| SF | L | N | M | FFT_M latency | Symbol latency | Symbol interval |
|---:|---:|---:|---:|---:|---:|---:|
| 5 | 4 | 32 | 128 | 180 | 419 | 128 |
| 5 | 8 | 32 | 256 | 313 | 680 | 256 |
| 7 | 1 | 128 | 128 | 180 | 614 | 128 |
| 7 | 2 | 128 | 256 | 313 | 875 | 256 |
| 7 | 4 | 128 | 512 | 567 | 1385 | 512 |
| 7 | 8 | 128 | 1024 | 1084 | 2414 | 1024 |
| 9 | 2 | 512 | 1024 | 1084 | 3185 | 1024 |
| 10 | 1 | 1024 | 1024 | 1084 | 4214 | 1024 |
| 12 | 1 | 4096 | 4096 | 4143 | 16476 | 4096 |

Throughput is **one symbol per `M` samples with no gaps**. The measured symbol
interval equals `M` exactly in every multi-symbol case, so the pipeline sustains
the full input rate and never stalls. This is the measurement behind the
no-backpressure interface decision.

Symbol latency depends on `N` as well as `M`: at `M = 1024` it is 2414 samples
for `N = 128` and 4214 for `N = 1024`, because the second FFT and the peak
tracker both scale with `N`.

### What these numbers are not

They are Simulink sample-clock latencies. They are **not** hardware latency, and
no clock frequency, `Fmax`, or resource figure exists yet. Nothing here has been
synthesized.

## Fixed-point configuration

### What is chosen and what is derived

Integer bits at every chosen boundary come from measured range analysis over
the committed golden vectors (`lora_sim.stage_ranges`) plus one guard bit, so
the swept word length only trades fraction bits. Policy is held constant so a
sweep changes one variable at a time:

| Property | Value | Why |
|---|---|---|
| Rounding | `Floor` | truncation, the cheapest option in HDL |
| Overflow | `Saturate` | a wrap would move the `argmax` |
| Guard bits | 1 | one binary doubling of the measured range |

Chosen boundaries: input IQ, reference ROM, complex multiply, partition
accumulator, second FFT after the `1/M` scale, magnitude², spectrum sum, and
confidence.

The two FFT widths are **not** chosen. `dsphdl.FFT` runs unnormalized, so its
output word length is its input word length plus `log2(FFTLength)` with the
fraction length unchanged. They are reported as derived values.

### Why decision preservation alone is not a criterion

The obvious acceptance rule — "the symbol decisions must not change" — is
satisfied by word lengths that are numerically useless, and the sweep says so
plainly. Every acceptance case keeps its exact MATLAB symbol at **8 bits**,
while the relative RMS error of the correlator output reaches **118%**.

The reason is in the decision-margin column: the relative gap between the
winning bin and the runner-up spans 0.16 to 1.00 across the acceptance set and
is mostly above 0.8. Breaking an `argmax` with that much separation takes an
enormous amount of quantization noise.

But `argmax` is not the only consumer. `decode_packet_soft` uses per-bin
magnitudes as reliability information, and a demodulator whose output is wrong
by tens of percent is worthless there. The selection therefore requires both:

1. every acceptance case decides the same symbol as MATLAB, and
2. the worst relative RMS error over every stage stays at or below
   `MaxRelativeRms`, default `1e-2`.

The 1% bound is an engineering choice, not a derived limit, and is stated as
one. Its rationale: at the −10 dB SNR acceptance point the magnitude² values
already vary by order 100% from noise alone, so holding quantization to 1%
keeps it roughly 20 dB below the physical variation the soft decoder is
designed to work with.

### Sweep results

15 cases at each word length, 90 fixed-point simulations, 3161 s total.

| Word length | Cases | Symbol matches | Worst relative RMS | Worst confidence error | Smallest decision margin |
|---:|---:|---:|---:|---:|---:|
| 8 | 15 | 15 | `1.180e+00` | `3.628e-01` | 0.160 |
| 10 | 15 | 15 | `2.922e-01` | `1.748e-01` | 0.227 |
| 12 | 15 | 15 | `7.334e-02` | `8.604e-02` | 0.232 |
| 14 | 15 | 15 | `1.805e-02` | `2.781e-02` | 0.236 |
| **16** | 15 | 15 | `4.561e-03` | `7.459e-03` | 0.237 |
| 18 | 15 | 15 | `1.142e-03` | `2.049e-03` | 0.237 |

Worst relative RMS per configuration:

| SF | L | M | 8 bits | 10 bits | 12 bits | 14 bits | 16 bits | 18 bits |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 5 | 4 | 128 | `1.902e-01` | `4.631e-02` | `1.205e-02` | `3.198e-03` | `8.980e-04` | `2.266e-04` |
| 5 | 8 | 256 | `1.242e-01` | `5.669e-02` | `1.434e-02` | `3.396e-03` | `8.579e-04` | `2.330e-04` |
| 7 | 1 | 128 | `1.993e-01` | `5.043e-02` | `1.242e-02` | `3.161e-03` | `7.856e-04` | `1.960e-04` |
| 7 | 2 | 256 | `1.675e-01` | `4.448e-02` | `1.063e-02` | `2.787e-03` | `6.844e-04` | `1.707e-04` |
| 7 | 4 | 512 | `1.751e-01` | `5.222e-02` | `1.227e-02` | `3.097e-03` | `7.987e-04` | `2.034e-04` |
| 7 | 8 | 1024 | `3.389e-01` | `1.133e-01` | `3.840e-02` | `9.696e-03` | `2.410e-03` | `5.635e-04` |
| 9 | 2 | 1024 | `3.943e-01` | `8.954e-02` | `2.271e-02` | `5.638e-03` | `1.419e-03` | `3.667e-04` |
| 10 | 1 | 1024 | `5.846e-01` | `1.492e-01` | `3.644e-02` | `8.877e-03` | `2.292e-03` | `5.846e-04` |
| 12 | 1 | 4096 | `1.180e+00` | `2.922e-01` | `7.334e-02` | `1.805e-02` | `4.561e-03` | `1.142e-03` |

Every point divides the error by roughly four per two added bits, as expected
for a purely fractional refinement.

**Selected: 16 bits** for the whole acceptance set. It is the smallest swept
word length that satisfies both criteria; 14 bits fails only because of
`SF12, L=1` at `1.805e-02`.

**14 bits is sufficient for the first hardware target.** At `SF7, L=8` — BW
125 kHz with `Fs = 1 MHz` — the error at 14 bits is `9.696e-03`, inside the 1%
bound. The larger word length is driven by the widest FFT in the acceptance
set, not by the configuration the board will run first.

The selection is derived from the committed table; the two criteria are encoded
in `run_fixed_point_sweep` as `MaxRelativeRms`, so re-running reproduces it
without re-deriving it by hand.

### Selected types at 16 bits

| SF | L | input | reference | product | accumulator | fftN | magnitude² | FFT_M out | FFT_N out |
|---:|---:|---|---|---|---|---|---|---:|---:|
| 5 | 4 | `sfix16_En11` | `sfix16_En9` | `sfix16_En3` | `sfix16_En3` | `sfix16_En6` | `ufix16_En0` | 23 | 21 |
| 5 | 8 | `sfix16_En14` | `sfix16_En8` | `sfix16_En2` | `sfix16_En2` | `sfix16_En6` | `ufix16_En-1` | 24 | 21 |
| 7 | 1 | `sfix16_En14` | `sfix16_En10` | `sfix16_En6` | `sfix16_En6` | `sfix16_En7` | `ufix16_En1` | 23 | 23 |
| 7 | 2 | `sfix16_En14` | `sfix16_En9` | `sfix16_En4` | `sfix16_En4` | `sfix16_En6` | `ufix16_En-1` | 24 | 23 |
| 7 | 4 | `sfix16_En14` | `sfix16_En8` | `sfix16_En2` | `sfix16_En2` | `sfix16_En5` | `ufix16_En-3` | 25 | 23 |
| **7** | **8** | `sfix16_En10` | `sfix16_En7` | `sfix16_En-1` | `sfix16_En-1` | `sfix16_En4` | `ufix16_En-5` | 26 | 23 |
| 9 | 2 | `sfix16_En12` | `sfix16_En8` | `sfix16_En1` | `sfix16_En1` | `sfix16_En4` | `ufix16_En-5` | 26 | 25 |
| 10 | 1 | `sfix16_En14` | `sfix16_En8` | `sfix16_En3` | `sfix16_En3` | `sfix16_En4` | `ufix16_En-5` | 26 | 26 |
| 12 | 1 | `sfix16_En14` | `sfix16_En7` | `sfix16_En1` | `sfix16_En1` | `sfix16_En2` | `ufix16_En-9` | 28 | 28 |

Negative fraction lengths are not a mistake: `magnitudeSquared` at `SF7, L=8`
reaches `1.05e6`, so the type is a 16-bit unsigned value scaled by `2^5`. The
FFT output columns are derived, not chosen.

Raw tables:

- [`simulink-m2-fixed-point-sweep.csv`](data/simulink-m2-fixed-point-sweep.csv)
- [`simulink-m2-fixed-point-cases.csv`](data/simulink-m2-fixed-point-cases.csv)
- [`simulink-m2-fixed-point-stages.csv`](data/simulink-m2-fixed-point-stages.csv)

### Range analysis is scoped, and that is a limitation

Integer bits follow the measured maxima of the acceptance corpus. A different
input regime — a front end with more headroom, a different AGC target, an
interferer — requires re-running the range analysis. The word length is the
transferable result; the fraction lengths are not.

## Joint timing/CFO estimator

The second subsystem separates whole-chip timing from carrier offset using the
signed dechirp bins of one preamble upchirp and one SFD downchirp. Because both
half-sum and half-difference are exact multiples of `1/2`, the whole estimator
is integer arithmetic in units of half a bin, and the DUT is compared against
MATLAB on **exact equality** rather than a tolerance.

| SF | L | N | Bin pairs | Coverage | Mismatches | Rejected pairs |
|---:|---:|---:|---:|---|---:|---:|
| 5 | 8 | 32 | 1 024 | exhaustive | 0 | 0 |
| 7 | 8 | 128 | 16 384 | exhaustive | 0 | 0 |
| 7 | 1 | 128 | 16 384 | exhaustive | 0 | 0 |
| 9 | 2 | 512 | 262 144 | exhaustive | 0 | 0 |

295 936 bin pairs, every one enumerated: this is a proof over the whole input
domain, not a sample. All five outputs — `correctionSamples`, `cfoHalfBins`,
`timingHalfChips`, `estimateValid`, `timingRejected` — match.

Raw table: [`simulink-m2-joint-sync.csv`](data/simulink-m2-joint-sync.csv).

The zero in the last column is itself a result. The plausibility guard that
zeroes an implausible timing correction is **unreachable** for in-range bins:
signed bins bound `|timingChips|` by `(N-1)/2`, so the correction cannot exceed
`(N-1)·L/2`, which never reaches the `M/2 + L` limit. The branch is kept for
callers that might search a wider range, and both the MATLAB test and this
Simulink run now pin it as inactive rather than leaving it silently dead.

The estimator consumes bins, not samples. Producing those bins — the chirp-aware
preamble detector and the blind search for the packet start — is not built.

## Real SX1262 symbol windows

The committed SX1262 → ZynqSDR captures are decoded by the authoritative MATLAB
receiver, the corrected symbol windows the correlator actually consumed are
extracted, normalized to unit RMS per packet, and replayed through the
fixed-point DUT at 16 bits.

| SF | L | M | Packets | Symbols | fixed == float | nominal == receiver | worst relative RMS |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 5 | 8 | 256 | 30 | 2340 | 2340 | 2340 | `8.409e-04` |
| 6 | 8 | 512 | 30 | 2040 | 2040 | 2040 | `8.772e-04` |
| 7 | 8 | 1024 | 70 | 4060 | 4060 | 4060 | `1.399e-03` |
| **total** | | | **130** | **8440** | **8440** | **8440** | `1.399e-03` |

All 130 committed packets, all 8440 consumed symbols: the 16-bit fixed-point
DUT decides exactly the symbol the floating-point correlator decides, and both
decide exactly what the MATLAB packet receiver decided. Worst confidence error
is `6.704e-03`. Zero packets contain a single differing symbol.

The `nominal == receiver` column is worth its own sentence. The DUT uses the
nominal reference chirp; the packet receiver additionally estimates a
phase-aligned reference from the preamble. On these captures that adaptive
reference changes **no** symbol decision, so the feature the DUT does not
implement is, for this corpus, not load-bearing at the symbol level. That is a
measurement on 130 packets, not a general claim.

Range analysis for this run is collected from the real windows themselves.
Selected types:

| SF | L | input | reference | product | accumulator | fftN | magnitude² |
|---:|---:|---|---|---|---|---|---|
| 5 | 8 | `sfix16_En13` | `sfix16_En8` | `sfix16_En2` | `sfix16_En2` | `sfix16_En6` | `ufix16_En-1` |
| 6 | 8 | `sfix16_En13` | `sfix16_En7` | `sfix16_En1` | `sfix16_En1` | `sfix16_En5` | `ufix16_En-3` |
| 7 | 8 | `sfix16_En13` | `sfix16_En7` | `sfix16_En0` | `sfix16_En0` | `sfix16_En3` | `ufix16_En-6` |

Raw tables:

- [`simulink-m2-real-iq-groups.csv`](data/simulink-m2-real-iq-groups.csv)
- [`simulink-m2-real-iq-packets.csv`](data/simulink-m2-real-iq-packets.csv)

### What 8440 symbols means, and a defect this run found

8440 is the number of symbols the decoder **consumed**: 78 per packet at SF5,
68 at SF6, 58 at SF7. It is not the number of windows the receiver produced.
While searching timing, the receiver demodulates every window up to an
energy-derived packet end, which overshoots: an SF7 packet yields about 133
windows of which 58 carry signal and the rest are the noise floor after the
transmission stopped.

The first version of this regression replayed all of them and reported 45%
agreement. The stage errors did not agree with that number — SF5 showed 0.6%
relative RMS with 46% of decisions differing, which is impossible — and the
contradiction is what exposed the cause. In the noise windows the fixed-point
`magnitudeSquared` was **identically zero across every bin**: their peak is
around `0.13` against a corpus range of `2.4e6`, so the whole spectrum fell
below the LSB and `argmax` returned bin 0. The double DUT on the same packet
was 133/133, which is what proved the structure was sound and the stimulus was
not.

Two things are worth keeping from that. Scoring `argmax` on noise is
meaningless in floating point too — it simply agrees with itself and hides. And
fixed point turned a silent nonsense into a loud zero, which is the more
useful failure mode.

## Limitations and open items

Blocking full M2 acceptance:

1. **No acquisition or packet framing.** The chirp-aware preamble detector, the
   blind search for the packet start, sync-word and SFD validation, and the
   packet-level framing state machine are not in the model. Symbol framing
   inside a known window (`symbolBoundary`) exists; packet framing does not.
   M2 is explicitly not complete with only the demodulator and the joint
   estimator verified.
2. **No reset port.** The interface defines `resetIn`, but the generated models
   have no reset input and persistent state is only cleared between
   simulations. Reset behavior is therefore unverified.
3. **Timestamp and metadata outputs are not implemented.** The interface
   contract defines `coarseSampleCount`, `fractionalToaSamples`, and
   `timestampValid`, and the M2 roadmap item requires verifying that interface.
   Nothing carries it yet.
4. **Verification taps are ordinary outports.** They would appear in generated
   HDL. Gating them out is an M3 task.
5. **No Verilog, cosimulation, or synthesis.** `makehdl` has not been run, so
   there are no resource, `Fmax`, or power numbers, and none are claimed.
6. **Real-signal coverage is one corpus.** 130 packets at SF5/SF6/SF7, all
   `L = 8`, all strong-signal OTA captures. This is not a sensitivity test and
   does not cover SF8–SF12, other `L`, or weak signals.

Deliberately out of scope for M2, with a documented software interface instead:
deinterleaving, Hamming FEC, dewhitening, and CRC. Also out of scope and staying
in software: TDoA association, delay calibration, and 2D multilateration.
