# ToA symbol-origin regression

Evidence date: 2026-09-10. Baseline: `e572c6d` on `main`.
All timestamps below are **measured in RTL simulation**, in accepted IQ samples.
These results are not board measurements or hardware calibration evidence.

## Cause and timestamp contract

The detector returns the FFT window origin of the first decision in its
confirmed eight-preamble/two-sync sequence. When that sequence moves to the
next FFT window at a large arrival phase, its window origin is already later
than the represented preamble chirp. The joint controller incorrectly added
the forward-only grid-resync skip, selecting the following preamble chirp.

Let `W` be that decision-window origin, `S` the samples per symbol and
`A = chips_to_boundary * samples_per_chip`. The chirp-search origin is
`W + wrap_centered(A, S)`, with the signed phase in `[-S/2, S/2)`.
The first full SFD search uses the same origin plus `10*S`.
The live grid still uses a forward skip modulo `S`; that skip is not a signed
timestamp displacement. The half-symbol tie belongs to the later decision
window and therefore uses the negative half-symbol displacement.

For the measured phase-512 case, `W=2048` and `A=512`.
The old search origin was 2560; the corrected origin is 1536.
The conversion uses the symbol-length parameter, not a phase-specific
constant applied to emitted metadata. The detector pulse/held-phase wiring,
generated HDL, MATLAB/Python golden models and golden vectors are unchanged.

## Acceptance matrix

The expected column is **derived from the stimulus**: `N` silent samples,
one 1024-sample non-preamble prefix, then the first preamble upchirp.
Thus its arrival is exactly `1024 + N`, independent of FFT window selection.

| Phase N | Before (measured) | After (measured) | Expected (derived) |
|---:|---:|---:|---:|
| 0 | 1024 | 1024 | 1024 |
| 8 | 1032 | 1032 | 1032 |
| 120 | 1144 | 1144 | 1144 |
| 296 | 1320 | 1320 | 1320 |
| 512 | 2560 | 1536 | 1536 |
| 700 | 2748 | 1724 | 1724 |
| 1000 | 3048 | 2024 | 2024 |
| 1023 | 2047 | 2047 | 2047 |

All eight updated runs exited successfully, emitted exactly one metadata
record and passed exact coarse equality and the fractional-range assertion.
The former NOTE/known-boundary exception is removed. At phase 1023 the old
implementation already returned the correct peak; this is preserved in the
measurements rather than extrapolating the phase-1000 error to it.

CI now includes phases 512, 700 and 1023 in addition to 0 and 296.
The controller unit stimulus explicitly locates chirp and decision-window
origins on either side of the signed wrap, including the half-symbol tie.
Its up/down peak offsets and half-sum rounding assertions remain in place.

## Executed checks

- `python -m pip install -e ".[dev]"`: succeeded.
- `python -m pytest`: **208 passed**, Python 3.14.0 / pytest 9.1.0.
- MATLAB R2025a: `cd('model/matlab'); results = run_tests; assertSuccess(results);`: passed.
- Simulink R2025a: `run_timestamp_metadata_regression` with `assert(report.passed)`: passed;
  all five metadata records, duplicate overflow and reset/order cases passed.
  Its CSV was written under ignored `tmp/toa_checks`, not over versioned evidence.
- Verilog-2001 compilation of `lora_joint_chirp_grid_controller`: passed.
- `git diff --check`: passed.

All 20 RTL benches listed in `.github/workflows/ci.yml` were compiled with
Icarus and exercised with VVP:

| Testbench | Result |
|---|---|
| `tb_lora_sample_counter_capture` | PASS |
| `tb_lora_iq_history_buffer` | PASS |
| `tb_lora_matched_filter_mac` | PASS |
| `tb_lora_matched_filter_search` | PASS |
| `tb_lora_matched_filter_search_sf7_l8` | PASS |
| `tb_lora_peak_triplet_capture` | PASS |
| `tb_lora_detector_timestamp_align` | PASS |
| `tb_lora_detector_timestamp_path` | PASS |
| `tb_lora_fft_detector_timestamp_path` | PASS |
| `tb_lora_packet_timestamp_axi_path` | PASS |
| `tb_lora_packet_toa_receiver_top` | PASS |
| `tb_lora_symbol_grid_resync` | PASS |
| `tb_lora_joint_chirp_grid_controller` | PASS |
| `tb_lora_joint_chirp_grid_path` | PASS (chips 0, 1, 2) |
| `tb_lora_joint_grid_completion` | PASS (all eight phases above) |
| `tb_lora_async_sample_fifo` | PASS |
| `tb_lora_clg400_gpreg_bridge` | PASS |
| `tb_lora_timestamp_metadata_join` | PASS |
| `tb_lora_axi_lite_status` | PASS |
| `tb_lora_receiver_control_wrapper` | PASS |

The eight-phase acceptance matrix also covers every CI completion plusarg.
Acceptance copies of that bench added only a timestamp `$display`; removing
that diagnostic was checked to reproduce the committed bench source exactly.
Duplicate long-running simulations were not required as separate evidence.
Raw local logs and matrix JSON are under ignored `tmp/toa_checks/`.

## Additional acquisition diagnostic

Detector-only traces at phases 508 and 511 produced no confirmed packet during
the stimulus, with both the baseline and corrected controller. A phase-512
positive control confirmed a packet at window origin 2048 with 64 boundary
chips before the same trace deadline. These traces stop on confirmation or
after the 17-symbol stimulus; they are not passing ToA regressions.

The controller change cannot affect acquisition before the first confirmation:
its search and feedback start only after that event. Thus these observations
identify a separate pre-existing acquisition limitation of this stimulus,
not a one-symbol timestamp correction. The exact metadata assertion is retained.
Exploratory full completion runs at 504, 508, 511 and 513 were interrupted
during this diagnosis and are not counted as passed. This report does not
claim an exhaustive successful sweep of every sample phase.

## Reproduce the phase matrix

From the repository root with Icarus installed:

```sh
iverilog -g2012 -DLORA_NAMESPACED_GENERATED \
  -s tb_lora_joint_grid_completion -o /tmp/lora_joint_grid_completion_tb \
  fpga/generated/fft-correlator-fixed/lora_fft_correlator_gen/*.v \
  fpga/generated/blind-detector/lora_blind_detector_gen/lora_blind_BlindDetector.v \
  fpga/generated/toa-interpolator/lora_toa_interpolator_gen/lora_toa_ToaInterpolator.v \
  fpga/wrappers/*.v fpga/tb/tb_lora_joint_grid_completion.sv
for n in 0 8 120 296 512 700 1000 1023; do
  vvp /tmp/lora_joint_grid_completion_tb +grid_phase=$n || exit 1
done
```
