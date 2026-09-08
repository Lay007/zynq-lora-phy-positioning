# Stage-by-stage receive-chain differential

This document describes `tools/export_stage_differential.py`, the reproducible
regression that walks one IQ capture and the PL symbol trace frozen from the
*same* packet through the receive chain and names the **first** stage at which
the reference model and the programmable logic stop agreeing.

It exists because the one-sided `+1 bin` decision bias needed a root cause
rather than a fitted correction. A `-1` adjustment applied at the symbol
decision would have made the payload CRC pass without explaining anything, and
would have broken as soon as the sample phase changed.

Related: [CLG400 symbol trace and first decoded payload](clg400-payload-session-2026-09-03.md),
[golden source of truth](ru/golden-source-of-truth.md).

## What is compared

Three independent symbol sources are evaluated per window.

| Source | Origin | Can it hide a receiver defect? |
|---|---|---|
| `pl` | the decision the PL froze into its trace | it *is* the thing under test |
| `reference` | the two-FFT correlator identity on the PL's own sample window | no; it is the model, but it sees the same samples |
| `expected` | the symbols the transmitter must have sent | **no**; rebuilt from the transmitter's serial log, it never sees the received IQ |

The `expected` column is what makes the ladder conclusive. It is produced by
`zlp1_payload` — the deterministic Heltec counter frame fixed by
`firmware/heltec-v4-sx1262-tx` — passed through `encode_lora_packet`, the
Python packet encoder pinned to the MATLAB golden vector
`model/matlab/golden/lora-phy-sf7-cr1.json`. Nothing in that path depends on
the capture, so a disagreement against it cannot be an artefact of the
receiver being wrong in a self-consistent way.

## The ladder

Stages are evaluated in the order the signal flows. The report blames the
first stage that diverges; later stages are still measured, because a failure
there is a consequence rather than a cause.

| Stage | Question it answers |
|---|---|
| `raw_iq` | is there a capture, is it unclipped |
| `iq_format` | does the stream correlate as an upchirp rather than its conjugate — I/Q polarity and swap |
| `sample_grid` | do the PL sample counts form one regular grid plus at most the one documented resync skip |
| `reference_chirp` | does the reference hold the expected unit-amplitude energy |
| `dechirp` | does the sample-wise dechirp agree with the two-FFT identity on identical upchirp windows |
| `correlator_power` | is the PL decision the reference peak or its runner-up — do both sides see the same spectrum |
| `peak_bin` | is the PL decision exactly the reference peak |
| `timing_cfo` | does the joint up/down estimator produce a timing and CFO figure |
| `symbol` | do the delivered symbols equal the transmitted ones |
| `symbol_timing_corrected` | do they agree once the joint sample correction moves the grid |
| `packet_decode` | does the corrected grid decode to the transmitter's exact bytes |

### Divergence versus tie-break

A stage counts as **diverged** only when a decision falls outside the
reference peak/runner-up pair. When the two sides swap two near-equal bins the
stage is reported as `tie-break` instead.

This is deliberate and threshold-free. A correlator peak that clears its
neighbour by a fraction of a decibel cannot be resolved identically by two
different implementations — decimation and the aliasing sum are different
operations off the symbol grid. Calling that a divergence would blame
`dechirp` for what is really a sample-phase problem three rungs down. Every
such swap observed on hardware sits below 0.35 dB of margin.

### What is excluded, and why

Two comparison points are excluded from the strict verdict and reported
explicitly rather than silently dropped:

- **the resync transition entry.** At the entry the skip follows, the PL
  decided on samples it then discarded, so its window and the reference window
  are provably different samples. `excluded_transition_entries` records it.
- **the padding-dependent tail.** The final block is filled to `sf_app`
  nibbles when the data does not divide evenly, and interleaving spreads those
  padding nibbles across every symbol of that block. The padding value is a
  transmitter choice the payload does not fix, so those symbols are not a
  sound comparison point. `payload_determined_symbol_count` on the encoder
  result defines the boundary; `padding_dependent_symbol_count` reports it.

Both exclusions are properties of the comparison, not of the receiver. Neither
removes a symbol that carries payload information.

## Running it

```bash
python tools/export_stage_differential.py \
    experiments/runs/20260904-clg400-iq-compare/clg400-trace-20260903T224859Z.json \
    --csv stages-seq30.csv --json stages-seq30.json
```

The IQ path is optional: when omitted it is taken from `serial.iq_capture` in
the trace, resolved beside the trace file. The exit code is `0` when no stage
diverged and `1` otherwise, so the tool is usable as a gate.

The CSV holds one row per window with the full pipeline exposed:
`pl_sample_count`, `dma_window_start`, `grid_window_start`,
`reference_phase_index`, `window_mean_i/q`, `dechirped_dc_i/q`, `dechirp_bin`,
`correlator_peak_power`, `correlator_second_power`, `correlator_margin_db`,
`reference_peak_bin`, `reference_second_bin`, `timing_correction_samples`,
`cfo_displacement_samples`, `pl_raw_symbol`, `pl_final_symbol`,
`corrected_final_symbol`, `expected_symbol`, and the per-row agreement flags.

## Result on the three simultaneous captures

Heltec sequences 30, 31 and 32, each a 1.5-million-sample RX1 DMA recording
captured concurrently with its 128-entry PL trace. Full data in
[`data/clg400-stage-differential-2026-09-08.json`](data/clg400-stage-differential-2026-09-08.json).

| Stage | seq 30 | seq 31 | seq 32 |
|---|---|---|---|
| `raw_iq` | agreed | agreed | agreed |
| `iq_format` | agreed | agreed | agreed |
| `sample_grid` | agreed | agreed | agreed |
| `reference_chirp` | agreed | agreed | agreed |
| `dechirp` | 57/57 | 57/57 | 55/57 (+2 tie-break) |
| `correlator_power` | 59/59 | 59/59 | 59/59 |
| `peak_bin` | 59/59 | 57/59 (+2 tie-break) | 59/59 |
| `timing_cfo` | agreed | agreed | agreed |
| **`symbol`** | **32/53** | **37/53** | **42/53** |
| `symbol_timing_corrected` | 53/53 | 53/53 | 53/53 |
| `packet_decode` | agreed | agreed | agreed |

Bin-error histograms of the delivered symbols:

| Capture | error 0 | error +1 | error −1 |
|---|---:|---:|---:|
| seq 30 | 32 | 21 | 0 |
| seq 31 | 37 | 16 | 0 |
| seq 32 | 42 | 11 | 0 |

**48 wrong symbols, every one of them exactly `+1`, and not one `−1`.**

### What this establishes

Everything upstream of the symbol decision agrees. `correlator_power` is
59/59 on all three captures, meaning the PL and the reference model always
computed the same spectrum; where `peak_bin` differs, the PL picked that
spectrum's own runner-up at a sub-0.35 dB margin.

That measurement rules out, on evidence rather than by argument, every
candidate that would have to act at or before the peak decision:

- an off-by-one or a `0 ↔ 127` wrap in the bin index;
- the sign of the cyclic shift, and the LoRa `+1` bin convention;
- MATLAB one-based against RTL zero-based indexing;
- I/Q polarity, swap, and conjugation;
- signed/unsigned conversion and the reference ROM phase;
- rounding or truncation inside the correlator.

Any of those would move the reported bin itself and would therefore appear at
`peak_bin` or earlier. None does.

The defect is at `symbol`: the sample phase at which the grid is placed. The
integer-chip resync removes the coarse quarter-symbol error but leaves a
residual inside the eight samples of a chip, and a sub-chip residual biases
the decision one way only. Applying the joint up/down sample correction to the
same windows takes all three captures to 53/53 with a valid packet decode and
zero bin adjustment.

### Why the bias can only be one-sided

The measurement above says the errors are all `+1` and never `-1`. That looked
like a signed defect, and it is not one.

The raw PL decisions of each packet — before any bin adjustment — land on
**exactly two adjacent bins**:

| Capture | raw errors, before adjustment | adjustment | surviving errors |
|---|---|---:|---|
| seq 30 | `{-1: 32, 0: 21}` | −1 | `{0: 32, +1: 21}` |
| seq 31 | `{0: 37, +1: 16}` | 0 | `{0: 37, +1: 16}` |
| seq 32 | `{0: 42, +1: 11}` | 0 | `{0: 42, +1: 11}` |

`raw_decision_bin_spread` is 2 in all three.

A residual sitting near the half-chip decision boundary puts each symbol's peak
close to a bin edge, and which way it rounds depends on the symbol value. The
packet therefore splits into two groups one bin apart. Only one integer bin
adjustment is available, so whichever group it fixes, the other is left wrong
by exactly one bin — always in the same direction, because the two groups sit
on the same side of each other.

The one-sidedness is a property of that split, not of the arithmetic. This is
also why the earlier empirical `-1` correction and the parity-guided search
could not work: shifting the adjustment does not remove the split, it only
exchanges which group is wrong.

The synthetic sweep confirms both halves. Beyond the half-chip boundary every
symbol tips together and the direction is simply the sign of the grid error —
a negative offset gives `-1`, a positive one gives `+1`, so a sub-chip residual
is *not* one-signed by itself. At exactly half a chip the packet splits, which
is the hardware condition:

| Injected grid error | Bin errors |
|---:|---|
| −6, −5 samples | all `-1` |
| −4 samples | split, `{-1: 26, 0: 27}` |
| −3 … +3 samples | none |
| +4 samples | split, `{0: 23, +1: 30}` |
| +5, +6 samples | all `+1` |

`tests/test_stage_differential.py` pins the split, the direction, and the
recovery.

### The controlled reproduction

`tests/test_stage_differential.py` builds a complete synthetic SF7 frame,
freezes a PL trace that agrees with the reference exactly, and then damages
one stage at a time:

- the undamaged chain reports **no divergence** at any stage, with a bin-error
  histogram of `{0: 53}`;
- injecting **half a chip** of grid error reproduces the hardware signature —
  first divergence at `symbol`, a one-sided `{+1}` histogram, every upstream
  stage still clean — and the joint estimator recovers exactly the injected
  offset, returning the chain to 53/53;
- conjugating the stream is blamed on `iq_format`.

The half-chip experiment is the direct confirmation: a sub-chip sample-phase
error, and nothing else, produces a one-sided `+1` bias with a clean
correlator underneath it.

## Evidence boundary

This is model-and-capture evidence. It uses real over-the-air recordings and
the PL's own frozen decisions, so it is stronger than simulation alone, but it
is not a packet-error-rate measurement and does not qualify the link. The
corrected-grid results are computed offline from the recorded IQ; the
receiver's own packet-rate implementation of the same correction is covered by
[`data/rtl-joint-chirp-grid-2026-09-04.json`](data/rtl-joint-chirp-grid-2026-09-04.json)
and still needs full-board routing, a cold boot, and a repeat capture before
any PER claim.
