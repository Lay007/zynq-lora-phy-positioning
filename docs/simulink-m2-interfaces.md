# M2 foundations: toolchain, interfaces, and stage vectors

[Русская версия](ru/simulink-m2-interfaces.md)

This document freezes the three things M2 needs before any `.slx` exists: the
measured MATLAB configuration, the receiver interface contract, and the
stage-level golden-vector format. Everything here is either a recorded
measurement or an explicit design decision; nothing is assumed.

## 1. Verified toolchain

Measured on the development machine, not taken from an installation list. Each
license was **checked out**, not only tested for presence.

| Property | Value |
|---|---|
| Host | Windows 10 Pro 10.0.19045, win64 |
| MATLAB | R2025a, version `25.1.0.2943329` |
| Install root | `C:\Program Files\MATLAB\R2025a` |
| License file | `licenses/license_WIN-F9DVUKQOSB0_968398_R2025a.lic` |

| Product | Version | License feature | `license("test")` | `license("checkout")` |
|---|---|---|---|---|
| Simulink | 25.1 | `SIMULINK` | pass | pass |
| Fixed-Point Designer | 25.1 | `Fixed_Point_Toolbox` | pass | pass |
| HDL Coder | 25.1 | `Simulink_HDL_Coder` | pass | pass |
| DSP HDL Toolbox | 25.1 | `DSP_HDL_Toolbox` | pass | pass |
| DSP System Toolbox | 25.1 | `Signal_Blocks` | pass | pass |
| HDL Verifier | 25.1 | `eda_simulator_link` | pass | pass |
| Communications Toolbox | 25.1 | `Communication_Toolbox` | pass | pass |
| Simulink Coder | 25.1 | `Real-Time_Workshop` | pass | pass |
| Embedded Coder | 25.1 | `RTW_Embedded_Coder` | pass | pass |

Two feature names do **not** follow the product names, which is worth recording
because a naive check reports the products as missing:

- HDL Coder is licensed as `Simulink_HDL_Coder`. `license("test","HDL_Coder")`
  returns `0` even though HDL Coder 25.1 is installed and usable.
- HDL Verifier is licensed as `eda_simulator_link`. `license("test","HDL_Verifier")`
  likewise returns `0`.

Reproduce with `model/simulink/report_toolchain.m`.

### What this does and does not prove

It proves the four products required by the M2 plan are installed and their
licenses can be obtained on this host. It does **not** prove that any particular
block is HDL-generatable, that the design meets timing, or that a synthesis tool
(Vivado) is installed and on the path. Those are M3 questions and are still open.

## 2. Frozen M2 interfaces

The DUT boundary is a streaming symbol demodulator. Everything below is the
contract that the Simulink model and, later, the generated Verilog must honor.

### 2.1 Data and flow control

| Signal | Direction | Type | Meaning |
|---|---|---|---|
| `iqIn` | in | complex, `double` then `sfix<W_in>_En<F_in>` | baseband sample at `Fs = L·BW` |
| `validIn` | in | `boolean` | `iqIn` carries a sample this cycle |
| `resetIn` | in | `boolean` | synchronous flush of all framing state |

**Flow control decision: no `ready` backpressure.** The DUT is a fixed-rate
sample-clocked pipeline. It accepts one sample per `validIn` cycle and can never
stall, because every stage is either combinational, a fixed delay line, or a
streaming FFT whose throughput equals its input rate. This is the documented
alternative to `valid/ready` required by the M2 plan.

The consequence is explicit and must be respected by the integration layer: the
DUT has no elastic buffer. If the AD936x sample path can produce bursts faster
than the processing clock, the buffering belongs upstream of the DUT, not
inside it. `validIn` may be deasserted freely; gaps are tolerated and do not
corrupt framing because all counters advance on `validIn` only.

### 2.2 Configuration and packet control

| Signal | Direction | Type | Meaning |
|---|---|---|---|
| `spreadingFactor` | compile-time | `uint8` | selects `N = 2^SF`; fixes FFT lengths |
| `samplesPerChip` | compile-time | `uint8` | `L = Fs/BW`; fixes `M = N·L` |
| `syncWord` | tunable | `uint8` | expected LoRa sync word |
| `implicitHeader` | tunable | `boolean` | header mode for the framing controller |
| `implicitPayloadBytes` | tunable | `uint8` | payload length when implicit |
| `codingRate` | tunable | `uint8` | `1…4` for CR 4/5…4/8 when implicit |

`spreadingFactor` and `samplesPerChip` are **compile-time**, not tunable. They
set FFT lengths and ROM depths; making them run-time would require the largest
FFT plus a variable-length ROM. The first hardware milestone is BW 125 kHz and
SF7, so this costs nothing now and is recorded as a limitation.

### 2.3 Symbol outputs

| Signal | Direction | Type | Meaning |
|---|---|---|---|
| `symbolIndex` | out | `uint16` | `argmax` bin, `0…N-1` |
| `symbolValid` | out | `boolean` | one cycle per demodulated symbol |
| `symbolBoundary` | out | `boolean` | first sample of the next symbol window |
| `confidence` | out | `ufix<W_c>_En<F_c>` | `peak / sum(magnitude²)`, in `(0,1]` |
| `peakMagnitudeSquared` | out | `ufix<W_p>_En<F_p>` | winning bin power |
| `spectrumSum` | out | `ufix<W_s>_En<F_s>` | denominator of `confidence` |

`confidence` is defined exactly as in MATLAB: the winning bin's magnitude²
divided by the sum of all `N` magnitude² values. The per-bin soft `metrics`
array of `lora_phy.fft_correlator_stages` uses a **median** noise-floor
estimate and stays outside the DUT: a streaming median over `N` bins is
expensive in HDL and the LLR path is a software-side consumer.

### 2.4 Acquisition and synchronization outputs

| Signal | Direction | Type | Meaning |
|---|---|---|---|
| `preambleDetected` | out | `boolean` | chirp-sequence detector asserted |
| `syncValid` | out | `boolean` | sync word and SFD transition confirmed |
| `timingOffset` | out | `sfix<W_t>` | whole-chip correction, from `(up-down)/2` |
| `cfoEstimate` | out | `sfix<W_f>_En<F_f>` | normalized CFO, from `(up+down)/2` |
| `acquisitionFailed` | out | `boolean` | candidate rejected before framing |

The joint estimator is the M1 result restated as an interface: the upchirp
dechirp bin mixes whole-chip timing and CFO; the downchirp bin flips the sign
of the timing term only. Half-sum gives CFO, half-difference gives timing.

### 2.5 Packet outputs and failure flags

| Signal | Direction | Type | Meaning |
|---|---|---|---|
| `headerValid` | out | `boolean` | explicit header CRC passed |
| `payloadLength` | out | `uint8` | decoded or configured payload length |
| `headerCodingRate` | out | `uint8` | decoded CR |
| `payloadByte` | out | `uint8` | payload byte stream |
| `payloadByteValid` | out | `boolean` | qualifies `payloadByte` |
| `payloadCrcOk` | out | `boolean` | payload CRC result |
| `headerCrcFailed` | out | `boolean` | explicit header rejected |
| `packetDone` | out | `boolean` | end of packet, flags are stable |

`payloadCrcOk` and `headerCrcFailed` are reported for **every** packet that
reached framing. Acquisition failures and CRC failures are never removed from a
PER denominator; that rule is inherited from M1 and applies to the Simulink
model unchanged.

### 2.6 Timestamp metadata

| Signal | Direction | Type | Meaning |
|---|---|---|---|
| `coarseSampleCount` | out | `uint64` | free-running PL sample counter latched at detection |
| `fractionalToaSamples` | out | `sfix<W_r>_En<F_r>` | sub-sample refinement |
| `timestampValid` | out | `boolean` | qualifies both timestamp fields |

Cross-station association, per-channel delay calibration, and 2D
multilateration are **software**. They are not in the DUT and will not be
generated to HDL. What M2 must verify is that the timestamp/metadata interface
carries enough information for the existing MATLAB solver, not that the solver
can be moved into the PL.

### 2.7 HDL boundary

Inside the DUT: FFT correlator, preamble/sync detection, joint timing/CFO,
symbol framing.

Documented software interface, deliberately outside the DUT for M2:
deinterleaving, Hamming FEC, dewhitening, header and payload CRC. The DUT emits
`symbolIndex`/`symbolValid` plus framing flags, and the PS/host performs the
bit-level chain. This keeps the first HDL boundary at the symbol stream, which
is where the sample-rate pressure ends.

## 3. Stage-level golden vectors

`export_correlator_stage_vectors` writes the committed acceptance vectors to
`model/matlab/golden/fft-correlator/`. The numerical source is
`lora_phy.fft_correlator_stages`, which also backs
`lora_phy.fft_correlator_metrics`, so the vectors cannot drift from the
receiver.

### 3.1 Comparison points

| Stage | Shape | Type | Definition |
|---|---|---|---|
| `input` | `M × C` | complex | aligned symbol windows |
| `reference` | `M × 1` | complex | `lora_phy.reference_chirp` |
| `referenceSpectrum` | `M × 1` | complex | `fft(reference)` |
| `conjReferenceSpectrum` | `M × 1` | complex | `conj(fft(reference))` |
| `fftM` | `M × C` | complex | `fft(input)` |
| `product` | `M × C` | complex | `fftM .* conjReferenceSpectrum` |
| `partition` | `N × C` | complex | `sum_r product(m + rN)` |
| `fftN` | `N × C` | complex | `fft(partition)/M` |
| `magnitudeSquared` | `N × C` | real | `abs(fftN).^2` |

`M = N·L`, `N = 2^SF`, `C` is the number of symbols in the window. Peak index
and confidence are per-symbol scalars and live in the manifest.

### 3.2 File format `zynq-lora-phy-stage-vectors-v1`

- `manifest.json` — schema version, generator, MATLAB release, per-case
  configuration and impairments, transmitted and expected symbols, expected
  confidence, and for each stage its shape, byte offset, length, scale
  summary, plus the SHA-256 of the payload file.
- `<id>.f64` — raw little-endian IEEE-754 `float64`. Stages are concatenated in
  the order above with no padding or headers. Elements are in MATLAB
  column-major order, so within a column the index is the streaming order and
  each column is one CSS symbol. Complex stages interleave `(real, imag)`.

The payload is deliberately raw so MATLAB, Simulink, Python, and a future
HDL testbench can all read it with `fread`, `numpy.fromfile`, or an equivalent,
without writing a parser. `lora_verify.read_stage_vectors` is the MATLAB
reader; `lora_verify.load_stage_manifest` verifies every checksum on load.

### 3.3 Committed cases

15 cases, 1.7 MB total, covering SF5/SF7/SF9/SF10/SF12, `L = 1/2/4/8`, single
and multi-symbol windows, AWGN down to −10 dB, carrier offset, and integer plus
fractional timing offset.

| Case | SF | L | M | Symbols | Impairment | Tx → Rx |
|---|---:|---:|---:|---|---|---|
| `sf7-l1-clean` | 7 | 1 | 128 | 3 | none | `0,45,127` → same |
| `sf7-l2-clean` | 7 | 2 | 256 | 2 | none | `13,100` → same |
| `sf7-l4-clean` | 7 | 4 | 512 | 1 | none | `63` → same |
| `sf7-l8-clean` | 7 | 8 | 1024 | 1 | none | `1` → same |
| `sf7-l8-awgn-p00` | 7 | 8 | 1024 | 1 | SNR 0 dB | `77` → same |
| `sf7-l8-awgn-m10` | 7 | 8 | 1024 | 1 | SNR −10 dB | `77` → same |
| `sf7-l8-cfo` | 7 | 8 | 1024 | 1 | +1500 Hz | `32` → `34` |
| `sf7-l8-timing` | 7 | 8 | 1024 | 1 | +3 samples, +0.40 frac | `32` → same |
| `sf7-l8-combined` | 7 | 8 | 1024 | 2 | −900 Hz, −2 + 0.25, −5 dB | `32,96` → `31,95` |
| `sf5-l8-clean` | 5 | 8 | 256 | 2 | none | `17,3` → same |
| `sf5-l4-awgn` | 5 | 4 | 128 | 1 | SNR −5 dB | `30` → same |
| `sf9-l2-clean` | 9 | 2 | 1024 | 1 | none | `300` → same |
| `sf9-l2-combined` | 9 | 2 | 1024 | 1 | +600 Hz, +1 + 0.75, 0 dB | `511` → `2` |
| `sf10-l1-clean` | 10 | 1 | 1024 | 1 | none | `1000` → same |
| `sf12-l1-clean` | 12 | 1 | 4096 | 1 | none | `4095` → same |

The CFO cases deliberately move the decision. An offset of `f` Hz shifts the
correlator peak by `f/BW · N` bins: `1500/125000 · 128 = 1.54 → +2` for
`sf7-l8-cfo`, and `600/125000 · 512 = 2.46` plus `+1` chip of timing wraps
`511 → 2` for `sf9-l2-combined`. These cases exist to exercise arithmetic on a
non-trivial spectrum, **not** to claim decoding accuracy under CFO; the
uncorrected shift is the expected behavior of a demodulator placed before the
CFO correction.

### 3.4 Regeneration and guard tests

```matlab
cd model/matlab
manifest = export_correlator_stage_vectors;
```

`TestCorrelatorStageVectors` enforces:

1. `fft_correlator_stages` reproduces `fft_correlator_metrics` bit-for-bit.
2. Each stage matches its algebraic definition.
3. The length-`N` recursive comb accumulator used by the Simulink DUT equals
   the reshape-and-sum used by MATLAB.
4. Case construction is deterministic across repeated calls.
5. Every noiseless case decodes its transmitted symbols exactly.
6. Every committed payload matches its manifest SHA-256 and is bit-identical
   to a freshly computed run — `MaxAbsError == 0`, not a tolerance.
