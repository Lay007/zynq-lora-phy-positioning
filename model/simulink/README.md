# Simulink implementation

This is stage two, after the MATLAB floating-point behavior is stable. No `.slx`
is committed: every model is rebuilt from a generation script, so deleting the
`.slx` and regenerating it is the normal workflow rather than a recovery step.

The measured toolchain, the frozen M2 interface contract, and the stage-vector
format are in
[`docs/simulink-m2-interfaces.md`](../../docs/simulink-m2-interfaces.md).

Verify the products and licenses M2 depends on:

```matlab
cd model/simulink
report = report_toolchain;
```

Presence in `ver` is not accepted as proof; every feature is checked out. Note
that HDL Coder is licensed as `Simulink_HDL_Coder` and HDL Verifier as
`eda_simulator_link`, so checking `HDL_Coder` or `HDL_Verifier` wrongly reports
them as absent.

## First DUT

Build the streaming correlator. The `.slx` is an output, never an input:

```matlab
cd model/simulink
info = build_fft_correlator_model;                                % SF7, L=8
info = build_fft_correlator_model(SpreadingFactor=9, SamplesPerChip=2);
```

Models are written to `generated/`, which is git-ignored. Deleting that
directory and re-running the builder is the normal workflow.

`DUT` implements the coherent FFT correlator with one block per MATLAB
comparison point:

```text
iqIn / validIn
    → InputFraming          symbol boundary from a mod-M sample counter
    → FFT_M                 dsphdl.FFT, length M = N·L, natural order,
                            unnormalized so it equals fft()
    → BinCounter            frequency bin index q = 0…M-1
    → RomReal / RomImag     conj(fft(reference)) as two ROMs addressed by q
    → Multiply              product = fftM .* conjReferenceSpectrum
    → PartitionAccumulate   y[q] = product[q] + y[q-N], an N-deep comb whose
                            last N outputs are the frequency partitions
    → FFT_N                 dsphdl.FFT, length N
    → ScaleByM              1/M, an exact power-of-two shift
    → MagnitudeSquared      |.|²
    → PeakTracker           first-maximum bin, peak, spectrum sum
    → Confidence            peak / max(spectrumSum, eps)
```

The partition accumulator is the one place where the Simulink structure
deliberately differs from the MATLAB expression. MATLAB reshapes the `M`
product bins to `N × L` and sums along `L`; the DUT cannot buffer a whole
symbol of bins, so it runs a length-`N` recursive comb and keeps the last `N`
outputs. `TestCorrelatorStageVectors` proves the two are equal.

`SpreadingFactor` and `SamplesPerChip` are compile-time: they set both FFT
lengths and the ROM depth, so a different configuration is a different
generated model. Everything else in the frozen interface contract is tunable
or a run-time signal.

The DUT exposes six production outputs (`symbolIndex`, `symbolValid`,
`confidence`, `peakMagnitudeSquared`, `spectrumSum`, `symbolBoundary`) and
eight verification taps (`stageFftM`, `stageProduct`, `stagePartition`,
`stageFftN`, `stageMagnitudeSquared`, `fftMValid`, `partitionValid`,
`fftNValid`). The taps carry signals that already exist internally, so they
cost ports rather than logic; gating them out of the HDL target is an M3 task
and is not done yet.

The first DUT implements only the coherent FFT-correlator path. Adaptive
preamble-reference estimation, the legacy polyphase fallback, packet decoding,
and CRC-based path selection remain outside the DUT until their resource and
mismatch trade-offs are measured.

## Second DUT: joint timing/CFO

```matlab
info = build_joint_sync_model(SpreadingFactor=7, SamplesPerChip=8);
```

`lora_joint_sync/DUT` consumes the dechirped peak bin of one preamble
upchirp and one SFD downchirp and separates whole-chip timing from carrier
offset — the M1 result that made the coherent branch deterministic on real
captures:

```text
upSigned        = signed bin of the upchirp peak,   [-N/2, N/2)
downSigned      = signed bin of the downchirp peak
cfoHalfBins     = upSigned + downSigned      (2 x the CFO in bins)
timingHalfChips = upSigned - downSigned      (2 x the timing in chips)
correction      = round(-timingChips * L),  zeroed when implausible
```

Working in halves of a bin removes every fractional value, so the whole
estimator is integer arithmetic and the DUT is **bit-exact** against
`lora_phy.joint_timing_cfo_from_bins`. No fixed-point tolerance applies and
none is claimed. `run_joint_sync_regression` enumerates the entire `N × N`
input domain where that is affordable.

## Regression

One command runs everything and fails loudly:

```matlab
cd model/simulink
results = run_simulink_regression;
```

```bash
matlab -batch "cd model/simulink; run_simulink_regression"
```

The shell form returns a nonzero exit code whenever Simulink and MATLAB
disagree. `run_correlator_regression` drives the DUT with the committed golden
`input` stage and compares `fftM`, `product`, `partition`, `fftN`, and
`magnitudeSquared` against the golden payload, plus symbol decision,
confidence, and the reference ROM contents. Results are written to
`docs/data/simulink-m2-stage-comparison.csv` and
`docs/data/simulink-m2-case-summary.csv`.

Measured results are published in
[`docs/simulink-m2-acceptance.md`](../../docs/simulink-m2-acceptance.md).

## HDL generation rules

- Use a named DUT subsystem as the only HDL Coder target.
- Keep test benches and visualization outside the DUT.
- Version the model, initialization script, HDL configuration, and vector-export
  script together.
- Generate Verilog, not VHDL, for the first ZynqSDR integration.
- Run fixed-point comparison and HDL cosimulation before Vivado synthesis.
- Never hand-edit generated algorithmic Verilog.
