# M2 acceptance: Simulink measurements

[Русская версия](ru/simulink-m2-acceptance.md)

Measured results for the executable Simulink model. Every number here comes
from a committed script and a committed table; nothing is estimated. The
interface contract, toolchain, and vector format are in
[M2 foundations](simulink-m2-interfaces.md).

M2 is **not complete**. This document records what has been measured so far and
names what still blocks acceptance.

## Reproducing

```matlab
cd model/simulink
results = run_simulink_regression;
```

The command raises an error on any mismatch, so

```bash
matlab -batch "cd model/simulink; run_simulink_regression"
```

returns a nonzero exit code when Simulink and MATLAB disagree. This was
verified by forcing the tolerance to `1e-20`: the run exits with code 1.

Deleting `model/simulink/generated/` before the run is safe and is part of the
check — every model is rebuilt from `build_fft_correlator_model`.

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

They are Simulink sample-clock latencies for a double-precision model. They are
**not** hardware latency, and no clock frequency, `Fmax`, or resource figure
exists yet. Nothing here has been synthesized.

## Limitations and open items

Blocking full M2 acceptance:

1. **Fixed-point types are not implemented.** The model is double only. Word
   lengths, rounding, overflow, and saturation policy are specified in the
   interface contract but not yet realized or swept.
2. **Only the symbol demodulator exists.** Preamble detection, sync/SFD
   validation, the joint timing/CFO estimator, and symbol framing into a packet
   are not in the model. M2 is explicitly not complete with only the
   demodulator verified.
3. **No real-IQ regression through Simulink.** The 130 committed SX1262 packets
   still run through MATLAB only. Symbol windows extracted from them have not
   been pushed through the Simulink DUT.
4. **HDL Coder has not been run.** `checkhdl`/`makehdl` have not been invoked on
   the DUT, so HDL-compatibility of every block is unproven. The verification
   taps are still ordinary outports and would appear in generated HDL.
5. **Reset behavior is unverified.** The interface defines `resetIn`, but the
   generated model has no reset port and the persistent state is only cleared
   between simulations.

Deliberately out of scope for M2, with a documented software interface instead:
deinterleaving, Hamming FEC, dewhitening, and CRC. Also out of scope and
staying in software: TDoA association, delay calibration, and 2D
multilateration.
