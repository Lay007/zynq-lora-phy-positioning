# Hardware timestamping and synchronized receiver timing

[Русская версия](ru/hardware-timestamping.md)

This document describes the engineering mechanism intended to carry the project
from the current single-receiver programmable-logic (PL) timebase to synchronized
LoRa time-of-arrival (ToA) measurements on several ZynqSDR receivers. The design
decision is recorded in
[ADR-0005](architecture-decisions/0005-hardware-timestamping-and-receiver-synchronization.md).

The important distinction is that **timestamping is not Linux receive time and
not DMA completion time**. The timestamp is tied to the accepted IQ sample
stream in PL and is captured by the LoRa timing event before software or the
network can add nondeterministic latency.

## 1. What already exists

The repository already contains the core pieces of the single-receiver timing
path:

- `fpga/wrappers/lora_sample_counter_capture.v` implements a free-running
  64-bit accepted-sample counter;
- `sample_valid` advances the counter by exactly one accepted complex sample;
- `capture` snapshots the pre-increment counter value and produces a one-cycle
  `capture_valid` pulse;
- `fpga/wrappers/lora_packet_timestamp_axi_path.v` refines the integer packet
  reference with a sample-rate correlation peak search and a fractional ToA
  interpolator;
- `fpga/wrappers/lora_timestamp_metadata_join.v` atomically joins the 64-bit
  coarse sample count with a signed Q12 fractional offset, where one LSB is
  `1/4096` sample;
- the resulting metadata is exposed to the processing system through the
  existing AXI/gpreg status path.

The current counter therefore already provides the correct local coordinate:
**number of accepted samples**, rather than number of FPGA clock cycles. Idle
cycles do not advance sample time.

The current timestamp can be written conceptually as

```text
Tlocal_samples = Ncoarse + Nfrac / 4096
```

where `Ncoarse` is the captured 64-bit integer sample index and `Nfrac` is the
signed Q12 fractional correction.

This is sufficient for repeatable timing inside one receiver, but it is not yet
a common time coordinate shared by several receivers.

## 2. Why three free-running counters are not enough

Three boards can each measure a packet very precisely and still produce useless
TDoA data if their timebases have unrelated origins or different rates.
Multi-receiver timing has three separate problems:

1. **Frequency alignment** — the receivers must agree on how long one sample is.
2. **Epoch alignment** — they must share a reproducible time reference such as a
   PPS edge.
3. **Path calibration** — fixed delays through cables, RF front ends, AD936x
   filters/interfaces, FPGA pipelines and detector logic must be measured and
   removed.

A GPS lock indication or disciplined oscillator addresses only part of this
problem. It does not by itself prove that sample index `N` on receiver A is the
same physical instant as sample index `N` on receiver B.

## 3. Proposed clock and epoch model

For M6 the preferred topology is:

```text
                 common frequency reference
                         (10/40 MHz)
                         /    |    \
                        /     |     \
                       v      v      v
                   ZynqSDR1 ZynqSDR2 ZynqSDR3
                      |        |        |
                      +--------+--------+
                               ^
                               |
                         common PPS/epoch
```

The exact electrical clock distribution depends on the board revision and must
be verified on the physical hardware before calling the receivers synchronized.
The `fishball7020` support in `F5OEO/maia-sdr:refactor` is useful because its
board design already exposes `pps` and `clk_10` ports and contains VCTCXO/GPSDO
control logic. That upstream implementation is a board-support reference, not a
proof that a particular local HAMGEEK/ZynqSDR revision is wired identically.

## 4. PPS should anchor the counter, not become the timestamp source

The PL sample counter remains the fine timebase. PPS is used to establish a
common epoch.

The preferred implementation is to keep the 64-bit accepted-sample counter
free-running and **snapshot it on each synchronized PPS edge**, rather than use
an asynchronous PPS edge to reset the counter directly:

```text
accepted IQ -----> sample_valid -----> 64-bit sample counter
                                          |          |
                                          |          +---- LoRa event snapshot
                                          |
PPS pin -> synchronizer -> edge detect ---+--------------- PPS snapshot
```

For receiver `i`:

```text
Npps_i   = sample counter captured at PPS
Nevent_i = sample counter captured for the LoRa ToA event
DeltaN_i = Nevent_i - Npps_i
```

`DeltaN_i` is the coarse packet time measured from the same epoch. A separate
`pps_sequence` or epoch identifier should be stored so software never combines
a packet referenced to PPS `k` on one receiver with PPS `k+1` on another.

This scheme has several advantages:

- the canonical counter semantics do not change;
- packet events near the PPS edge can be reasoned about explicitly;
- PPS loss does not destroy the local free-running timebase;
- residual sample-rate drift can be measured from consecutive PPS snapshots;
- reset/re-arm behavior is separated from synchronization behavior.

The PPS input is asynchronous to the sample domain unless proven otherwise. It
must therefore pass through an explicit synchronizer/CDC boundary before edge
detection. The synchronization latency must be deterministic or measured and
included in calibration.

## 5. Frequency coherence and drift measurement

Epoch alignment alone is not sufficient. If the ADC/sample clocks differ by
`epsilon`, the timestamp difference drifts with elapsed time after PPS.

Consecutive PPS snapshots give a direct measurement:

```text
samples_per_pps_i = Npps_i[k+1] - Npps_i[k]
```

For nominal sample rate `Fs`, the receiver can monitor

```text
rate_error_i = samples_per_pps_i - Fs * Tpps
```

with `Tpps = 1 s` for ordinary 1 PPS. A shared reference should make this error
small and stable; the measurement is still retained as evidence rather than
assuming lock is perfect.

For the first TDoA experiment the preferred configuration is a genuinely common
reference distributed to all receivers. Independently disciplined oscillators
may be studied later, but they add residual phase/rate uncertainty that is not
needed for the first validation.

## 6. LoRa event timestamp path

The production timestamp is captured by the LoRa timing path, not by the host.
The current receiver already separates coarse and fractional refinement:

```text
AD936x IQ
   |
   v
LoRa acquisition / packet timing
   |
   +---- integer sample reference
   |          |
   |          v
   |    sample-rate peak search ----> Ncoarse
   |                                  |
   |                                  +------+
   v                                         |
fractional ToA interpolator ----> Nfrac Q12 |
                                             v
                                      atomic metadata
```

`lora_packet_timestamp_axi_path.v` intentionally uses the refined
`peak_sample_count` as the final coarse field rather than the earlier packet
start count. The fractional interpolator then supplies the sub-sample correction.

For synchronized operation the packet record is extended conceptually with the
PPS anchor:

```text
receiver_id
pps_sequence
pps_sample_count
packet_sample_count
fractional_toa_q12
sample_rate
sync_status
calibration_id
```

The timing value relative to the epoch is

```text
R_i = (packet_sample_count_i - pps_sample_count_i)
      + fractional_toa_q12_i / 4096
```

and the uncalibrated time from the epoch is `R_i / Fs_i`.

## 7. Delay calibration

TDoA needs propagation-time differences, not differences in receiver pipeline
latency. For each receiver define a fixed or slowly varying calibrated delay
`D_i` that includes all reproducible contributions between the chosen physical
reference plane and the timestamp event. Depending on the final bench this can
include:

- antenna/RF cable and splitter delay;
- analog RF/baseband group delay;
- AD936x digital filter and interface latency;
- sample-domain CDC or FIFO latency when it affects the timestamp reference;
- deterministic LoRa detector/search latency;
- any fixed PPS input/synchronizer skew relevant to the epoch anchor.

The corrected ToA coordinate is

```text
t_i = R_i / Fs_i - D_i
```

and the TDoA observation is

```text
Delta_t_ij = t_i - t_j
```

For RF propagation the corresponding range-difference observation is
approximately

```text
Delta_r_ij = c * Delta_t_ij
```

where `c` is the propagation velocity used by the positioning model.

Calibration must be evidence-based. A useful first bench injects the same RF
signal into two or three receivers through a splitter and known cable lengths.
The measured timestamp difference is then dominated by receiver/cable delay
rather than geometry. Repeating the measurement across reboot, re-arm, gain,
sample-rate and temperature conditions tells us which terms are truly fixed.

## 8. Optional timestamped raw-IQ debug stream

Phil Greenland's `pgreenland/plutosdr-hdl-quantulum` is a valuable reference for
observability. Its RX timestamp block is inserted between a channel packer and
DMA and carries a 64-bit timestamp through an asynchronous FIFO before
periodically inserting timestamp words into the DMA stream.

For a Tezuka/Fishball integration the analogous debug boundary is:

```text
util_ad9361_adc_pack
        |
        v
optional RX timestamp/debug adapter
        |
        v
axi_ad9361_adc_dma
```

This is useful for proving which IQ sample corresponds to a hardware timestamp
and for comparing offline MATLAB processing against PL events. It is **not** the
primary ToA mechanism: the normal positioning path should latch the counter in
PL when the LoRa event occurs. This keeps the timing result independent of DMA
buffer size, Linux scheduling and Ethernet/USB latency.

Scheduled TX timestamping, similar to Greenland's `util_upack2_timestamp`, is
outside the first RX/TDoA milestone.

## 9. Fishball/HAMGEEK integration boundary

The project does not vendor or fork the entire Tezuka/Maia HDL tree. The planned
integration surface is deliberately small:

```text
hardware/fishball7020/
    README.md
    upstream.lock
    patches/
    build.sh
```

The initial upstream reference is
`F5OEO/maia-sdr:refactor@79119c57dff1ea1d969e3453644819f081ef6dcd`.
A future `upstream.lock` must pin the exact revision used to build a tested
bitstream. The patches should only expose the synchronization inputs, connect
the project timing path, and optionally add raw-IQ timestamp observability.

Before applying this integration to a physical board, verify at minimum:

- exact Zynq device/package and speed grade;
- PS/DDR configuration;
- AD9361/AD9363 digital interface mode and pinout;
- reference-clock topology;
- PPS and external-clock connector/pin mapping;
- voltage levels and I/O standards;
- startup/reset behavior.

A successful build for `fishball7020` is not by itself evidence that an arbitrary
Zynq-7020 + AD9363 board is electrically compatible.

## 10. Verification sequence

The mechanism is accepted progressively rather than by one end-to-end test.

### Gate A — existing single-board timebase

Keep the existing RTL regression for accepted-sample counting, capture timing,
wraparound and atomic coarse/fractional metadata. No PPS work may silently
change those semantics.

### Gate B — PPS capture in one receiver

Drive a known PPS source into PL. Verify exactly one epoch event per pulse,
monotonic `pps_sequence`, stable samples-per-PPS and defined behavior when a
LoRa event occurs close to PPS.

### Gate C — two receivers

Feed the same clock/reference, PPS and split RF signal to two receivers. Record
`Npps`, packet coarse/fractional ToA and calibration state for many packets.
The important metric is the distribution and drift of corrected `Delta_t_12`,
not merely whether both receivers detect the packet.

### Gate D — three receivers

Repeat with three receivers, estimate fixed channel offsets, reboot/re-arm the
system and show that the calibrated offsets are reproducible. Store raw evidence
and configuration in the repository.

### Gate E — geometry

Move the transmitter to known positions, retain the synchronization/calibration
state, form `Delta_t_12` and `Delta_t_13`, and feed them into the existing 2D
multilateration model. Report bias, standard deviation, outliers and rejected
packets rather than only a map point.

## 11. Failure modes to detect explicitly

The implementation should expose status for at least:

- missing or duplicate PPS;
- PPS interval outside tolerance;
- reference/PLL not locked where such status exists;
- sample-counter discontinuity or reset;
- stale/mismatched PPS sequence between packet records;
- metadata overflow;
- detector/ToA result without a valid epoch anchor;
- calibrated offset version mismatch;
- DMA overflow in raw-IQ debug mode.

A timestamp should not be marked synchronization-valid merely because a 64-bit
number is present.

## 12. Relationship to upstream work

The design intentionally separates ownership:

- this repository owns LoRa timing semantics, sample-count timestamps,
  synchronization metadata, calibration and TDoA evidence;
- `F5OEO/maia-sdr` provides a useful `fishball7020` board-support/build reference;
- `pgreenland/plutosdr-hdl-quantulum` provides a useful RX/TX timestamp-stream
  reference implementation.

The Greenland reference is pinned at
`d70102267713f5bbc99805be5f4f08b0a07766cb` and is MIT licensed. If its source
is copied or adapted, its copyright and MIT permission notice must be preserved
with the derived code. Merely using the architecture as a reference does not
make the Pluto firmware a runtime dependency of this project.

## 13. Definition of success for the first synchronized prototype

The first prototype is successful when three receivers can observe the same
LoRa transmission and produce records tied to the same verified epoch, with a
common/verified sample-frequency basis, calibrated fixed delays and stable
inter-receiver ToA differences. At that point the positioning solver consumes
hardware-derived TDoA rather than timestamps reconstructed from host capture
arrival times.

Absolute UTC time, scheduled TX and FDoA are useful later extensions, but they
are not required to prove the first synchronized LoRa TDoA chain.
