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
    → AccumSum/AccumDelay   y[q] = product[q] + y[q-N], an N-deep comb whose
                            last N outputs are the frequency partitions
    → FFT_N                 dsphdl.FFT, length N
    → ScaleByM              1/M, an exact power-of-two shift
    → MagnitudeSquared      |.|²
    → SpectrumSum           running sum of the N magnitudes of one symbol
    → PeakTracker           first-maximum bin and its value
    → Confidence            peak / max(spectrumSum, peak, floor)
```

The accumulators are primitive blocks rather than MATLAB Function code, so
every fixed-point output type, rounding mode, and overflow policy is an
explicit block setting. Only the counters and the argmax comparison, which
never change word length, live in MATLAB Function blocks.

The partition accumulator is the one place where the Simulink structure
deliberately differs from the MATLAB expression. MATLAB reshapes the `M`
product bins to `N × L` and sums along `L`; the DUT cannot buffer a whole
symbol of bins, so it runs a length-`N` recursive comb and keeps the last `N`
outputs. `TestCorrelatorStageVectors` proves the two are equal.

`SpreadingFactor` and `SamplesPerChip` are compile-time: they set both FFT
lengths and the ROM depth, so a different configuration is a different
generated model. Everything else in the frozen interface contract is tunable
or a run-time signal.

The DUT exposes eight production outputs (`symbolIndex`, `symbolValid`,
`confidence`, `peakMagnitudeSquared`, `spectrumSum`, `symbolBoundary`,
`symbolSampleCount`, `timestampValid`) and eight verification taps
(`stageFftM`, `stageProduct`, `stagePartition`, `stageFftN`,
`stageMagnitudeSquared`, `fftMValid`, `partitionValid`, `fftNValid`).

The taps are optional: `build_fft_correlator_model(IncludeVerificationTaps=false)`
omits them, and `run_hdl_compatibility_check` builds that way so the HDL
boundary carries only production signals. Production outputs come first in the
port order, so dropping the taps renumbers nothing.

`resetIn` clears the three counters and both streaming FFTs. Nothing else needs
reset: the accumulator delay line is gated off for the first `N` bins of a
symbol and the peak tracker re-initializes at bin 0, so neither can read
pre-reset state once the counters restart. `run_reset_regression` proves it by
driving one waveform, asserting reset, driving a second in the same simulation,
and requiring the second half to match a standalone run exactly.

`symbolSampleCount` carries the sample index of each symbol's first sample,
latched at `symbolBoundary` and queued through the pipeline. That is the
timestamp half of the metadata contract; the fractional ToA is not implemented
and stays in software, because it needs the sample-rate matched filter that
belongs to acquisition.

The confidence denominator is `max(spectrumSum, peak, floor)`. At the decision
instant the running sum already contains the peak, so this equals the MATLAB
definition exactly; on the intermediate cycles of a symbol it keeps the ratio
at or below one, which stops the fixed-point divider saturating on values that
are never sampled.

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

## Frequency-only DUT

```matlab
info = build_frequency_estimator_model( ...
    SpreadingFactor=7, SamplesPerChip=8);
```

`lora_frequency_estimator/DUT` retains only `cfoHalfBins = upSigned +
downSigned` as `int16` and `estimateValid`. Inputs and outputs are registered, so latency
is two clocks and Vivado sees a real register-to-register path. Bin inputs are
`uint8` for SF5–SF8 and `uint16` for SF9–SF12. The physical
conversion stays outside the DUT:

```text
cfoHz = cfoHalfBins * bandwidthHz / (2 * 2^SF)
carrierHz = configuredSdrCentreHz + cfoHz
```

`run_frequency_estimator_regression` compares it exactly with the unchanged
joint timing/CFO MATLAB golden model over 295936 bin pairs. At SF7/BW125 the
output step is 488.281 Hz and the ideal nearest-bin quantization error is at
most 244.141 Hz. This is not an absolute RF calibration; SDR and transmitter
reference errors remain part of the reported carrier offset.

## Third DUT: acquisition acceptance

```matlab
info = build_acquisition_model(SpreadingFactor=7, PreambleSymbols=8);
```

`lora_acquisition/DUT` consumes the correlator's symbol stream and decides
whether it looks like a LoRa acquisition sequence: `PreambleSymbols` upchirps
near bin 0, then two sync symbols near the bins the sync word encodes, each
within `BinTolerance` on a circular metric. Outputs are `preambleDetected`,
`syncValid`, `acquisitionFailed`, and `symbolsSeen`.

Integer arithmetic again, so it is bit-exact against
`lora_phy.validate_acquisition_bins`. `run_acquisition_regression` compares
them over exact, drifted, wrapped, and rejected sequences plus seeded random
ones.

The sync-word scale is a fixed **8** per nibble, not `2^(SF-4)`; a MATLAB test
pins that over all 256 sync words and SF7…SF12.

It validates a symbol-aligned candidate against **absolute** bin targets, which
is the right check only after timing and CFO have been corrected. Finding a
packet in the first place is the next DUT.

## Fourth DUT: blind packet-start detection

```matlab
info = build_blind_detector_model(SpreadingFactor=7, PreambleSymbols=8);
```

`lora_blind_detector/DUT` finds packets without being told where they begin,
and it does so without a sliding correlation. The preamble repeats one upchirp,
so it is periodic with a symbol; a window starting `d` chips after a boundary
dechirps to bin `d` whatever `d` is, and consecutive windows repeat that bin.
Detection is therefore a predicate over the last `PreambleSymbols + 2` bins of a
correlator that is simply left running, and the bin itself carries the
whole-chip timing offset.

Outputs are `detected`, `preambleDetected`, `syncValid`, `preambleBin`,
`chipsToBoundary`, and `binsSeen`. Sync is checked at
`preambleBin + 8 x nibble` rather than at absolute bins, which also makes the
check invariant to CFO — CFO displaces preamble and sync equally.

Integer arithmetic again, so it is bit-exact against
`lora_phy.detect_preamble_run`. `run_blind_detector_regression` compares them
per symbol over placed packets at non-chip-aligned offsets, with noise and CFO,
plus random and edge-case bins, and sweeps all 256 sync words.

`preambleDetected` and `syncValid` are separate for a measured reason: on the
free-running grid a window can straddle the preamble-to-sync boundary and lose
the first sync symbol to the stronger half of its own window. Across an
alignment sweep of one whole symbol, preamble detection passes at 100 % and
sync at 97 %. Sync belongs after realignment by `chipsToBoundary`.

Generated Verilog: 0 multipliers, 0 RAMs, 168 register bits.

`preambleDetected` is evaluated on the newest `PreambleSymbols` bins as soon
as they exist, not on the full register. Gating it on the full register makes
it wait for the two sync windows, and a realignment derived from it can then
never take effect before the sync word has gone past — at any preamble length.
`lora_phy.detect_preamble_only` is the shared definition.

## Composed front-end

```matlab
info = build_receiver_frontend_model(SpreadingFactor=7, SamplesPerChip=4);
```

`lora_receiver_frontend/DUT` wires the correlator, the blind detector, and a
thin `ResyncPolicy` into one loop. The subsystems are copied from their own
builders rather than rebuilt, so there is one definition of each.

Realignment works by **withholding samples**, not by loading a counter. The
streaming FFT frames on its own count of valid samples, so writing a phase
into `InputFraming` moves the boundary flag and the timestamps and leaves the
FFT framing where it was — measured, and the bins did not move. Dropping `s`
samples shifts the grid by `s`, and `s = chipsToBoundary * L`.

`run_frontend_regression` checks the property that only exists once the blocks
are connected: a packet at a sample offset the receiver is never told must
demodulate to the same payload as an aligned one. Four offsets, none a
multiple of `L`, all recover the same 34 payload symbols.

## Fifth DUT: packet framing

```matlab
info = build_framing_model(HeaderSymbols=8);
```

`lora_framing/DUT` routes sync, SFD, header and payload, then returns to
idle. It mirrors `lora_phy.packet_frame_step`, which is why that reference
keeps its state in arguments rather than persistent variables: the two have
to be the same machine written twice, and a shape that only works in one of
them invites divergence.

Re-arming is as much the point as routing. The front-end realigns once per
reset, so without a stage that knows a packet has ended, the receiver
acquires one packet and then ignores the radio.

Phase travels as `uint8` — 0 idle, 1 sync, 2 sfd, 3 header, 4 payload.
Names for people in the reference, numbers for HDL Coder in the DUT, mapped
in one place in the regression. `headerSymbols` and `payloadSymbols` are
input ports rather than compile-time constants, because LoRa derives the
payload count from the decoded header and that has to be able to arrive at
run time even though nothing supplies it yet.

`run_framing_regression` compares per symbol on exact equality and fails if
the stimulus stops completing packets or stops exercising a rejection: an
FSM that parks after one packet passes every single-packet test, so the
test set has to make that impossible.

The SFD reference needs no ROM of its own —
`lora_phy.downchirp_reference_spectrum` derives it from the upchirp table at
a complemented address with the imaginary part negated, which is a mask and
a sign flip. The SFD validation DUT itself is not built yet; only the
MATLAB reference and `lora_phy.validate_sfd_bins` exist.

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

## Fixed point

```matlab
info = build_fft_correlator_model(DataType="fixed", WordLength=16);
report = run_fixed_point_sweep;
```

Integer bits per boundary come from measured range analysis over the committed
golden vectors (`lora_sim.stage_ranges`) plus one guard bit, so the word length
only trades fraction bits. Rounding is `Floor` and overflow saturates at every
chosen boundary; both are held constant so a sweep changes one variable at a
time.

The two FFT widths are **not** chosen. `dsphdl.FFT` runs unnormalized, so its
output word length is its input word length plus `log2(FFTLength)` with the
fraction length unchanged. `lora_sim.fixed_point_types` reports them as derived
values.

Selection needs two criteria, not one. Preserving symbol decisions alone is
satisfied by absurdly small word lengths, because the gap between the winning
bin and the runner-up is wide in most acceptance vectors. The sweep therefore
also bounds the relative RMS error and records `DecisionMargin` so a passing
point can be told from a lucky one.

## Real SX1262 windows

```matlab
report = run_real_iq_regression(WordLength=16);
```

The committed captures are decoded by the MATLAB receiver, the corrected symbol
windows it consumed are extracted through `ReturnSymbolWindows`, normalized to
unit RMS, and replayed through the fixed-point DUT. Range analysis for this run
comes from the real windows themselves: the integer bits of a fixed-point design
must follow the stimulus it will see, and the capture gain of one recording
session must not decide the word length.

Only the windows the decoder actually consumed are replayed. The receiver
demodulates past the end of a packet while searching timing, and that tail is
the noise floor; replaying it scores `argmax` on noise and stretches the range
analysis across seven decades for no signal. The first version of this
regression did replay it, and reported 45% agreement until the cause was found.

The report separates two questions that must never be mixed: whether fixed point
reproduces floating point on real signal statistics (both use the nominal
reference, so any difference is quantization), and how often the DUT's nominal
reference agrees with the packet receiver's preamble-estimated adaptive
reference, which the DUT does not implement.

## HDL compatibility

```matlab
report = run_hdl_compatibility_check(WordLength=16);
```

Runs `checkhdl` on each named DUT with `TargetLanguage` set to Verilog and
records every message. Note that HDL Coder settings go through `hdlset_param`;
`set_param`'s `TargetLang` is Simulink Coder's C/C++ selector and rejects
`"Verilog"`.

This stops at the compatibility checker. Generation, synthesis, and selected
post-route measurements are separate reproducible M3 steps below. HDL
cosimulation is still unavailable because no HDL simulator is installed.

## HDL generation (first M3 step)

```matlab
report = run_hdl_generation(WordLength=16);
```

Generates Verilog for all eight hardware-bound DUTs into `fpga/generated/` and
reads HDL Coder's own operator counts and delay-balancing report. Those counts
are inferred operators and must not be read as LUT/FF/DSP/BRAM.

```matlab
report = run_synthesis(Part="xc7z020clg484-1");
```

Drives Vivado out of context for synthesis resource and timing estimates.

```matlab
report = run_implementation(Part="xc7z020clg484-1");
```

Places and routes boundary-register wrappers around the FFT correlator and ToA
interpolator, then records post-route timing and vectorless power at the 4 MHz
application clock in `docs/data/simulink-m3-post-route.csv`. This remains a
core-only OOC estimate: it excludes board clocking, AXI, package I/O, the
processing system, and the AD936x interface, and it is not measured rail power.
Cosimulation is still not run because no HDL simulator is installed.

The measured counts are in
[`docs/simulink-m2-acceptance.md`](../../docs/simulink-m2-acceptance.md). The
headline for planning: the correlator costs 34 multipliers and 64 RAMs at
SF7/L=8/16 bits, and HDL Coder adds 34 cycles of latency on top of the model.

## HDL generation rules

- Use a named DUT subsystem as the only HDL Coder target.
- Keep test benches and visualization outside the DUT.
- Version the model, initialization script, HDL configuration, and vector-export
  script together.
- Generate Verilog, not VHDL, for the first ZynqSDR integration.
- Run fixed-point comparison before synthesis; HDL cosimulation still has no
  simulator to run on.
- Never hand-edit generated algorithmic Verilog.
