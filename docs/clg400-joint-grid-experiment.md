# Next hardware experiment: joint-grid receiver on the board

This is the experiment that closes, or refutes, the sample-phase root cause
identified in [stage-differential.md](stage-differential.md). It is written to
be executed verbatim.

The claim under test is narrow and falsifiable:

> The one-sided `+1 bin` symbol bias is caused by the sample phase left
> unresolved by the integer-chip resync. A receiver that applies the joint
> up/down sample correction in PL will deliver symbols that equal the
> transmitted symbols, with no bin adjustment, on captures where the previous
> build produced a two-bin split.

Everything needed to decide this offline already exists: the reference model,
the packet encoder, and `tools/export_stage_differential.py`. What is missing
is a board that actually applies the correction.

## Why this experiment and not a PER run

A packet-error-rate campaign now would measure the defect, not the link. The
previous build decoded 3 payloads in 16 at a strong signal level; that number
is a property of where each packet happened to land on an unaligned grid. PER
is only meaningful once the symbol stage agrees, which is exactly what this
experiment establishes.

## Prerequisites

The joint up/down estimator is already proven in the reference model, in
packet-rate RTL simulation, and in portable out-of-context synthesis at
71.266 MHz against a 62.5 MHz requirement
([`data/rtl-joint-chirp-grid-2026-09-04.json`](data/rtl-joint-chirp-grid-2026-09-04.json)).
It has **not** been routed in the complete board design.

Step 0 is therefore a build, not a measurement:

```bash
# From the repository root, with Vivado 2021.1 on PATH.
vivado -mode batch -source fpga/board/clg400/system_project.tcl
vivado -mode batch -source fpga/board/clg400/build_bitstream.tcl
vivado -mode batch -source fpga/board/clg400/export_hw_platform.tcl
```

Gate before going near the board: zero routing errors, zero critical warnings,
post-route WNS and WHS both positive. The previous accepted board build closed
at +0.031 ns WNS and +0.035 ns WHS, so this is known to be tight — if the
router lands negative, re-run with `AggressiveExplore` and the post-route
physical optimization pass, which `build_bitstream.tcl` already does by
default. **Do not deploy a bitstream that missed timing**; one earlier attempt
routed to −0.003 ns and was correctly discarded.

Then package and deploy the SD image exactly as
[`clg400-payload-session-2026-09-03.md`](clg400-payload-session-2026-09-03.md)
describes: back up the active `system_top.bit`, checksum it, copy the new one
to a temporary file on the same mount, compare checksums, rename atomically,
sync, and re-verify in place. Cold boot. Do not touch QSPI.

## Transmitter — Heltec WiFi LoRa 32 V4.3 / SX1262

Firmware `zynq-lora-heltec-v4-sx1262-tx` 0.2.0, serial on `COM10` at 115200.

| Setting | Value |
|---|---|
| Frequency | 868.100 MHz |
| Bandwidth | 125 kHz |
| Spreading factor | 7 |
| Coding rate | 4/5 |
| Sync word | 0x12 |
| Preamble | 12 symbols |
| Payload CRC | on |
| IQ | normal |
| Payload | `counter`, length 32 (the `ZLP1` frame) |
| TX power | **−9 dBm** |
| Periodic transmission | **off** — single `send` only |

The transmitter defaults back to 0 dBm after its own power cycle, so set and
**read back** −9 dBm before every attempt. `stop` before and immediately after
each `send`; never issue `start`. Keep both antennas fitted.

Hold TX power fixed. Raising it will not change the bias — the residual is a
property of the grid, not of SNR — and changing two variables at once would
make the result unattributable.

## Receiver — CLG400 ZynqSDR board B, RX1

After the cold boot the AD9361 comes up at 30.72 MS/s and must be returned to
the LoRa profile. The attribute order matters and getting it wrong returns a
bare `EINVAL`; the script already encodes the correct order:

```sh
sh /path/to/restore_rx_profile.sh
```

It must read back exactly:

```text
BBPLL:1024000000 ADC:32000000 R2:16000000 R1:8000000 RF:4000000 RXSAMP:1000000
```

| Setting | Value |
|---|---|
| RX sample rate | 1 MS/s |
| RX LO | 868.100 MHz (reads back 868,099,998 Hz) |
| RF bandwidth | 200 kHz |
| Gain control | **manual**, both channels |
| Hardware gain | **50 dB**, both channels |
| RX FIR / TX FIR | both enabled, 128-tap decimate/interpolate by 4 |

Then confirm the overlay:

```sh
sh /path/to/verify_board_b_cold_boot.sh
```

Expect `fpga_manager` reporting `operating`, both `0x4C4F5241` signatures
present, page one answering with the `0x53590000` symbol marker, and a status
of `0x00011243` — receiver enabled in both domains, formatted RX activity,
no sticky overflow.

## What to capture

**Twelve** individually commanded transmissions. Each attempt must produce
**both** artefacts from the same packet, or it does not count:

1. a raw RX1 DMA recording — 1,500,000 complex samples of interleaved
   little-endian int16 I/Q, i.e. 6,000,000 bytes, 1.5 s at 1 MS/s;
2. the frozen 128-entry PL symbol trace, armed before the transmission and
   read after it.

Twelve is chosen deliberately: the previous builds gave 10 and 16 attempts, so
twelve is directly comparable and is enough to separate "every capture agrees"
from "most do", which is the only distinction this experiment has to make. It
is *not* enough for a PER figure and must not be reported as one.

```powershell
$env:CLG400_SSH_PASSWORD = [System.Net.NetworkCredential]::new(
  '', (Read-Host -AsSecureString 'CLG400 SSH password')).Password
python tools/capture_clg400_iq_trace_pair.py `
    --password-env CLG400_SSH_PASSWORD `
    --known-hosts fpga/build/clg400-board/known_hosts.current `
    --connect-timeout 20 --port COM10 --attempts 12 `
    --run-dir experiments/runs/<date>-clg400-joint-grid
```

`capture_clg400_iq_trace_pair.py` does both halves in one attempt: it arms the
trace, starts the DMA recording so it brackets the transmission, sends once,
reads the frozen trace and streams the recording back over the same SSH
connection. It refuses an attempt whose recording is short, because a
truncated packet is worse than a missing one - it still looks like data. The
2026-09-03 session did this by hand.

The board runs from a RAM disk, so its host key is regenerated on every boot.
Re-pin it for the current power cycle before the run:

```bash
ssh-keyscan -T 8 192.168.40.1 > fpga/build/clg400-board/known_hosts.current
```

Also record, per attempt: the transmitter's reported `TX seq`, `len`,
`start_ms` and `duration_ms`; the capture sequence; `preamble_bin`; and the
`DEBUG` bits, including bit 8 (grid realigned).

Keep the raw IQ out of Git — `experiments/runs/` is ignored. Commit only the
JSON summaries and their SHA-256 hashes, as the previous sessions did.

## Analysis — the exact commands

For every attempt:

```bash
python tools/export_stage_differential.py \
    experiments/runs/<date>-clg400-joint-grid/clg400-trace-<stamp>.json \
    --csv stages-<stamp>.csv --json stages-<stamp>.json
```

The IQ path is taken from `serial.iq_capture` in the trace. The exit code is
`0` when no stage diverged.

For continuity with the previous session, also run:

```bash
python tools/analyze_clg400_iq_trace.py \
    experiments/runs/<date>-clg400-joint-grid/clg400-trace-<stamp>.json \
    experiments/runs/<date>-clg400-joint-grid/rx1-iq-<stamp>.bin
```

## What confirms the hypothesis

The prediction is specific. On the joint-grid build:

| Quantity | Predicted |
|---|---|
| `first_divergent_stage` | `null` on the large majority of attempts |
| `symbol` stage | agreed — delivered symbols equal transmitted symbols |
| `raw_decision_bin_spread` | **1**, not 2 |
| `bin_error_histogram` | `{0: 53}` |
| `bin_adjustment` in the trace decode | 0 |
| `DEBUG` bit 8 | set on every capture |
| Payload CRC valid | on the large majority of attempts |
| `joint_chirp_timing.correction_samples` | small, since PL already applied it |

`raw_decision_bin_spread` is the sharpest single number. On the previous build
it was 2 on all three analysed captures — the packet's raw decisions split
across two adjacent bins, which is what forces a one-sided residual no integer
adjustment can remove. If the PL correction works, that split collapses to a
single bin and the spread becomes 1. **A spread of 1 with a valid CRC is the
result that confirms the root cause.**

## What refutes it, and what each failure would mean

This is the part worth reading before the bench is packed up.

- **Spread stays 2, `symbol` still diverges one-sided.** The PL correction is
  not reaching the grid. Check `DEBUG` bit 8 and the withheld-guard arithmetic
  first: the coarse resync deliberately withholds a 16-sample guard that the
  late request must add back together with the signed joint correction. A sign
  error there would leave the residual untouched or double it.
- **Spread becomes 1 but the errors move to a constant non-zero offset.** The
  correction is being applied with the wrong sign or the wrong guard. The
  offline `joint_chirp_timing.correction_samples` in the report tells you the
  size and direction the model wanted; compare it against the skip the trace
  actually shows.
- **Spread becomes 1, CRC passes, but only on some attempts.** Then the
  remaining failures are a *different* effect and the sample-phase story is
  closed. Look at SNR and at `correlator_margin_db` in the CSV before assuming
  anything.
- **An earlier stage diverges.** `iq_format`, `sample_grid`, or `peak_bin`
  going red would mean the new build changed something upstream that the
  previous one had right. The ladder names it directly; that is what it is
  for.

## Result — 2026-09-08: refuted for this build

The experiment was executed. The joint-grid board design was routed
(post-route WNS +0.062 ns, WHS +0.011 ns, TNS/THS 0, 100 % of nets routed,
zero errors), the routed netlist was confirmed to contain `u_joint_grid_timing`,
`u_grid_resync`, `u_toa_search`, `u_iq_history` and `u_receiver`, the bitstream
was installed on the SD card against a checksum with the previous image backed
up, and the board rebooted onto it. Eleven paired captures were taken under the
documented profile. Full data in
[`data/clg400-joint-grid-result-2026-09-08.json`](data/clg400-joint-grid-result-2026-09-08.json).

**The prediction failed.** `raw_decision_bin_spread` stayed at 2 on ten of the
eleven captures. It did not collapse to 1.

The reason is specific, and it is the "wrong guard" branch of the failure list
below rather than a defect in the root cause:

| Quantity | Baseline arm | Joint-grid arm |
|---|---:|---:|
| Resync skips per capture | 1 | 1 |
| `skip` − `mod(chipsToBoundary + 2**(SF−2), 2**SF)·L` | **0** on 12/12 | **−16** on 11/11 |
| Offline joint correction still needed, mean | +0.83 samples | **+19.8 samples** |
| `raw_decision_bin_spread` | 2 on 7/12 | 2 on 10/11 |

The coarse resync withholds the 16-sample `FINE_GUARD_SAMPLES` on every
capture, exactly as designed. **The late fine request that must return that
guard together with the signed joint correction never arrives**: every trace
still shows exactly one resync skip, and the correction the offline estimator
then needs moves from a mean of +0.83 samples to +19.8. This build is therefore
strictly worse than the one it replaces — it removes sixteen samples and never
gives them back.

### What is not refuted

The root cause itself. Applying the joint up/down correction offline to these
same eleven captures takes ten of them to a fully agreeing symbol stage and a
valid packet decode, exactly as it did on the baseline arm. What failed is this
build's ability to apply that correction, not the correction.

### Reproduced offline, and the defect named

The failure was then reproduced in simulation without the bench.
`tb_lora_joint_grid_completion` drives the packet at a non-zero arrival phase
(`+grid_phase=N`, a silence prefix rather than a partial chirp so the stimulus
is not itself an artefact). At any non-zero phase:

```
search_failed=1  fine_resync=0  state=IDLE
peakboundary=1   macreadmiss=0  range_error=0
```

**This is not the board's mechanism, and it should not be reported as one.**
The abort trigger differs — a peak at the search boundary here, a history read
miss there — and probing at detection shows why: with a silence prefix the
detector still reports `preamble_bin = 0` and `chips_to_boundary = 0`, so the
coarse resync removes nothing and the search faces the full injected offset
against a ±16-sample radius. `FINE_GUARD_SAMPLES must cover SEARCH_RADIUS` is
asserted in the controller, so a residual that large is outside what the design
claims to handle. The simulated abort is a property of this stimulus.

What it does establish is the *consequence* of any abort, whatever causes it:
the search fails, no fine request is issued, and the coarse resync has already
withheld the guard. That consequence is what the board showed.

**That asymmetry is the defect.** Withholding the guard is unconditional;
returning it was conditional on the estimate succeeding. Any search failure,
through any of the three paths, left the grid permanently sixteen samples
short — strictly worse than never attempting the correction. It is why this
build measured worse than the one it replaced rather than merely no better.

The fix makes the return unconditional: every abort path now issues a fine
request carrying the bare `FINE_GUARD_SAMPLES` with a zero correction, so a
declined estimate degrades to exactly the coarse-only grid. A new
`search_abort_error` output feeds `toa_peak_boundary_error`, because a silent
abort is what made this cost a full bench run to find.

| Arrival phase | Searches | Aborted | `timing_valid` | `fine_skip` |
|---:|---:|---:|---:|---:|
| 0 | 2 | 0 | 1 | 23 (guard + correction 7) |
| 64 | 1 | 1 | 0 | **16** (bare guard returned) |
| 512 | 1 | 1 | 0 | **16** |

The regression now requires the guard back whatever the estimate does. The
controller, joint-path, receiver-top and CLG400 bridge regressions are
unchanged by it, and the joint path still reports `fine_skip=27`.

**Still open, and the next thing to settle:** why the board's search hits a
history read miss on every packet. It remains unreproduced offline — the
simulation reaches an abort by a different route. What is now known is that it
is deterministic and phase independent, so the next steps are:

- Establish why the detector reports `preamble_bin = 0` for a packet delayed by
  a silence prefix. Either the testbench delay is not the same thing as a real
  arrival phase, or the reported bin does not carry it; both matter, because
  the coarse resync depends on that bin.
- ~~Correlate the read miss with `preamble_bin` on the board.~~ **Done
  2026-09-09, and it refutes the phase hypothesis.** Fourteen packets, the
  sticky word cleared before each: `read_miss` on **14 of 14**, across
  `preamble_bin` 5 to 118, with an identical sticky word every time and
  `toa_peak_boundary_error` clear throughout. The miss does not depend on where
  the packet lands — it is deterministic on every packet. That rules out a
  marginal history-depth or timing effect and points at a systematic
  addressing or counter-domain error in the joint search. It also confirms the
  simulated boundary abort and the board's abort are different events.

### The board's read miss, reproduced offline

`tb_lora_joint_grid_completion` takes `HISTORY_DEPTH` as a parameter. At the
production 65536 the buffer never fills in this stimulus, `oldest_sample_count`
stays 0, and the "read too old" half of the miss condition is unreachable. On
the board the count runs into the millions and that half is always live.

Building the same test with a shallow history reproduces the board's flag
exactly:

```bash
iverilog -g2012 -DLORA_NAMESPACED_GENERATED -s tb_lora_joint_grid_completion   -Ptb_lora_joint_grid_completion.HISTORY_DEPTH=4096 -o /tmp/jg.vvp <sources>
vvp /tmp/jg.vvp
```

| `HISTORY_DEPTH` | Result |
|---:|---|
| 65536 | passes; 2 searches, no abort, `fine_skip=23` |
| 4096 | `macreadmiss=1`, every other flag clear |

That single flag, alone, is precisely what the board reported. **But it is the
same flag reached by a different route, and the board was then measured
directly to settle which.**

The miss condition has two halves: a read below `oldest_sample_count`, and a
read at or above `next_sample_count`. The receive-stream reset zeroes the
history counters, so `oldest` stays 0 until 65536 samples accumulate — 65.5 ms
at 1 MS/s. Sending a packet immediately after the reset therefore makes a
too-old read impossible. With the transmitter prepared beforehand and the
interval measured at the serial write rather than at the response:

| arm → send | read miss |
|---:|---|
| 0.2 ms ×4 | set |
| 3000 ms ×2 | set |

At 0.2 ms only a few hundred samples exist and detection lands near twelve
thousand, far short of the 65536 needed before anything is overwritten. Nothing
can have aged out, yet the miss occurs. **The board's failing read is ahead of
the stream, not behind it.** The shallow-history simulation reproduced the flag
through a `TOO_OLD` read and so matched the symptom, not the mechanism; it must
not be cited as the board's failure.

A future read points at one asymmetry. Both searches read
`coarse_start − SEARCH_RADIUS` through `coarse_start + REF_SAMPLES +
SEARCH_RADIUS`. The down search always waited for that window via
`STATE_WAIT_DOWN_DATA`. **The up search did not** — it launched as soon as the
shared search was free, whether or not its window had arrived.
`STATE_LAUNCH_UP` now waits on the same condition against `up_ready_count`.

The guard fix already makes this failure harmless rather than harmful.

A further step is now clearly worth its cost: `history_next_sample_count`,
`history_oldest_sample_count` and `history_samples_retained` are left
unconnected in `lora_clg400_gpreg_bridge`, so the retained window cannot be
read from the PS. Exposing them would say immediately whether the failing read
is too old or in the future, which splits the remaining hypotheses in half.

The guard fix makes an abort harmless rather than harmful. It does not deliver
the correction, and the joint-grid build should not be re-deployed as an
improvement until the abort itself is understood.

### Where to look next

`lora_joint_chirp_grid_controller` has three paths that reach `STATE_IDLE`
without asserting `fine_resync_valid`:

1. `search_failed` during the upchirp search;
2. `search_failed` during the downchirp search;
3. a rounded timing estimate outside `±FINE_GUARD_SAMPLES`, which sets
   `timing_range_error` and a zero `fine_skip`.

The first two emit no status at all, and `timing_valid` is left unconnected in
`lora_packet_toa_receiver_top`, so a frozen trace cannot tell them apart. That
observability gap is why this took a full bench run to find, and it is the same
gap `DEBUG` bit 8 was added to close for the coarse aligner.

The 15-bit diagnostic sticky word does separate them, and it names path 1 or 2:

| Diagnostic sticky | Baseline build | Joint-grid build |
|---|---|---|
| value | `0x0058` | `0x0218` |
| `toa_mac_read_miss_error` | clear | **set** |
| `toa_peak_boundary_error` | set | clear |

`toa_peak_boundary_error` carries `joint_grid_timing_range_error`, and it is
**not** set on the joint-grid build, so path 3 — a rejected out-of-range
estimate — did not fire. `toa_mac_read_miss_error` is set only when the joint
controller is active. **The abort is a `search_failed` caused by an IQ history
read miss:** the joint up/down search asks the history buffer for samples it
will not serve, the search fails, the controller returns to `STATE_IDLE`
without asserting `fine_resync_valid`, and the guard is never returned.

That makes the next step concrete: the history the joint search reaches back
to, not the timing budget, is what the packet-rate RTL regression did not
model. `HISTORY_DEPTH` is 65536 samples; the search's coarse start and the
guard-shifted grid together need to be checked against what the buffer
actually still holds at the moment the down search launches.

**The prerequisite for the next attempt is an observable "fine correction
applied" flag beside `DEBUG` bit 8, plus a sticky bit per abort reason.**
Without it the next build cannot distinguish "the estimator never ran" from
"it ran and was rejected" any better than this one could.

Until that build exists, the previous integer-chip image is the better one to
run: it is the arm whose skip matches the formula exactly. It is preserved on
the card as `system_top.bit.pre_jointgrid_20260908T173805Z`.

## Guard return, verified on hardware — 2026-09-09

The board design was rebuilt with both changes and closes better than the one
before it: post-route WNS +0.264 ns, WHS +0.034 ns, 100 % of nets routed. The
routed netlist still carries every joint-grid cell. Evidence:
[`data/clg400-guard-return-2026-09-09.json`](data/clg400-guard-return-2026-09-09.json).

**The guard return works.** Every capture now shows *two* resync skips instead
of one:

| seq | preamble bin | coarse skip | fine skip | total | formula | total − formula |
|---:|---:|---:|---:|---:|---:|---:|
| 76 | 41 | 936 | 16 | 952 | 952 | **0** |
| 77 | 21 | 72 | 16 | 88 | 88 | **0** |
| 78 | 74 | 672 | 16 | 688 | 688 | **0** |
| 80 | 86 | 576 | 16 | 592 | 592 | **0** |
| 81 | 29 | 8 | 16 | 24 | 24 | **0** |

Against `−16` on eleven of eleven captures before the fix. The delivered grid
now lands exactly on the coarse formula, so the joint-grid build is no longer
worse than the integer-chip build it replaces. That was the whole point of
making the return unconditional.

The analysis tool was corrected alongside: its `sample_grid` rung allowed one
resync skip, which was right for the integer-chip build and wrong for this one.
A coarse-plus-fine pair is now the expected shape.

**What is still not fixed.** The joint estimate itself is still declined — the
search continues to hit a history read miss — so the grid degrades to
coarse-only rather than being refined. Adding the missing data-ready wait to
the up search did **not** remove the miss: sending a packet 0.1 ms after the
stream reset, where nothing can have been overwritten, still produces it. The
failing read is still ahead of the stream and it is not the up search's first
read.

### The read miss, explained to the sample

The fine skip lands around trace entry 53 — roughly fifty symbols, not the
dozen the geometry predicts. That number turned out to be the whole answer.

`lora_iq_history_buffer` raises `read_miss` for **two different things**:

```verilog
wire read_write_collision = sample_valid && (read_addr == write_addr);
...
if (read_in_range && !read_write_collision) read_valid <= 1'b1;
else                                        read_miss  <= 1'b1;
```

A sample outside `[oldest, next)` is one. A read address that equals the write
address on a cycle when a sample arrives is the other, and it is reported
identically. The joint search reads a **fixed** window 9.75 symbols behind the
write pointer. While it runs the write pointer advances, and after a full
65,536-sample wrap it reaches that window. The collision fires, `read_miss`
feeds `search_failed`, and the estimate is abandoned.

The model predicts the timing exactly:

```text
samples from trace start to the fine skip = DEPTH − lookback + coarse_advance
```

| seq | preamble bin | coarse advance | fine skip at sample | minus advance |
|---:|---:|---:|---:|---:|
| 80 | 86 | 336 | 55888 | 55552 |
| 78 | 74 | 432 | 55984 | 55552 |
| 76 | 41 | 696 | 56248 | 55552 |
| 81 | 29 | 792 | 56344 | 55552 |
| 77 | 21 | 856 | 56408 | 55552 |

**55552 on all five, zero residual** — the slope against the advance is exactly
1. `65536 − 55552 = 9984` samples, 9.75 symbols, which is precisely the
lookback from the write pointer to the read window at search start.

This supersedes the future-read conclusion above. That was reached by
elimination — a too-old read is impossible so soon after a stream reset — and
the elimination missed this third cause. The up-search data-ready wait added on
the strength of it is correct and harmless, but it was not the fix.

### Root cause: the receiver got one clock per sample

The receiver's `sample_clk` came from `util_ad9361_divclk/clk_out`
(`lora_overlay_injection.tcl`, `clk_sel` tied to GND). Two static facts fix
what that clock is:

- `util_clkdiv` is instantiated with its defaults, `SEL_0_DIV = "4"`, and
  `BUFGMUX_CTRL` selects `I0` when `clk_sel` is 0. The output is the input
  divided by four.
- The AD9361 data clock is four times the sample rate. That is what makes the
  overlay's own comment - "62.5 MHz at the 250 MHz XDC maximum" - come out
  right: 250/4, at 61.44 MS/s.

Multiply them and the divider output is the sample rate itself. **The receiver
had exactly one fabric clock per sample, and no choice of AD9361 sample rate
changes that**, because both terms scale together. The 62.5 MHz the design is
written and constrained for exists only at the maximum sample rate, and even
there it is one clock per sample.

Measured rather than inferred, with ADI's clock monitor inside `axi_ad9361`
(`ADI_REG_CLK_FREQ` at `0x79020054`, against `fclk0` read from the PS clock
tree as 99,999,999 Hz):

| AD9361 sample rate | `CLK_FREQ` | AD9361 data clock | ratio to sample rate |
|---:|---:|---:|---:|
| 1.00 MS/s | 2624 | 4.0039 MHz | 4.004 |
| 2.00 MS/s | 5248 | 8.0078 MHz | 4.004 |
| 4.00 MS/s | 10496 | 16.016 MHz | 4.004 |
| 8.00 MS/s | 20992 | 32.031 MHz | 4.004 |
| 15.36 MS/s | 40306 | 61.505 MHz | 4.004 |
| 30.72 MS/s | 80613 | 123.00 MHz | 4.004 |

Linear over the whole range, so the receiver clock at the LoRa profile was
4.0039/4 = **1.001 MHz**, one clock per sample.

That single fact explains the whole investigation:

- The joint search costs 135,443 clocks. The SFD deadline is 2304 samples,
  which at one clock per sample is 2304 clocks. The search is **fifty-nine
  times** over its deadline and cannot fit at any profile.
- It therefore never completes. The history read window sits 9,984 samples
  behind the write pointer, so it ages out 65,536 - 9,984 = 55,552 samples
  after the search is armed - and 55,552 is well short of the 135,443 the
  search would need. The abort is the age-out, every time.
- **The read miss and the missed deadline are the same root cause**, which is
  why every attempt to fix one of them left the other in place.

Three independent measurements agree: the abort lands 55,552 samples after the
phase-corrected origin with zero residual across five captures; the fine skip
appears 50 to 51 symbols after the coarse resync in the traces; and
`toa_search_busy` is held 60 ms against the 55.5 ms the model predicts, on a
poll with 13.8 ms granularity.

An earlier estimate in this document put the clock at 1.9 to 3.2 MHz. It was
derived from that same busy window while assuming the search ran to
completion, and it was wrong by about a factor of two in one direction and
sixty in the other - the search does not complete, so its duration measures the
age-out rather than the cost. The number above is measured at a register, not
derived.

And it explains why no regression caught it.
`tb_lora_joint_chirp_grid_path` checks the deadline as
`SFD_SAMPLES * CLOCKS_PER_SAMPLE_CEIL` with `CLOCKS_PER_SAMPLE_CEIL = 63`, and
`tb_lora_joint_grid_completion` offers `+sample_gap=63` as the setting that
"reproduces the board's density". Sixty-three is the assumption, not the
board: a fifty-nine-fold overshoot was scored as 135,443 against 145,152 and
read as comfortable. No simulation could catch it, because nothing in the RTL
says the fabric clock and the sample rate are tied together on this platform.

**This is a design-level problem, not a bug to patch.** The joint up/down
estimator as specified cannot complete inside the SFD while the receiver is
clocked from the AD9361 data clock, at any sample rate. The options are to
clock the receiver from a fixed PL clock, to cut the search cost by about
sixty, or to stop requiring the correction inside the SFD.

### The fix: a fixed receiver clock

The receiver now has its own clock, and the samples cross into it.

`lora_overlay_injection.tcl` adds a `clk_wiz` fed from `sys_cpu_clk` producing
62.5 MHz, a `proc_sys_reset` for the new domain held until the MMCM locks, and
drives `lora_clg400_bridge/sample_clk` from it. `util_ad9361_divclk/clk_out`
stays connected, but only as `rx_clk`, carrying arriving samples.

62.5 MHz is not a free choice. It is the frequency the design is already
written and constrained for, and the last board build closed at `WNS +0.264 ns`
against it, which puts the routed ceiling near 63.5 MHz. The 71.266 MHz on
record is out-of-context synthesis of the receiver alone, not the routed board;
treating those two numbers as interchangeable would be the same class of
mistake as the clock itself. At 62.5 MHz and 1 MS/s the SFD deadline is
2304 * 62.5 = 144,000 clocks against the 135,443 the search needs - a 6 %
margin, thin but positive, and now a measured quantity rather than an
assumption.

The crossing is `lora_async_sample_fifo`, a small dual-clock FIFO with
Gray-coded pointers, not a toggle handshake. On the old clock `rx_valid` is
asserted on essentially every `rx_clk` cycle, because the clock *is* the sample
rate, so a handshake with acknowledgement would pass one sample per round trip
and drop most of the stream. A bare toggle would work at this rate and fail
silently if the sample rate were ever raised; the FIFO turns that case into an
explicit `wr_overflow`.

### Measuring it rather than believing it

The estimate this section replaces was wrong because it was derived and then
reported alongside measurements. The same build therefore carries two
independent ways to check the claim.

`axi_gpreg_lora` now instantiates two ADI clock monitors: monitor 0 on
`util_ad9361_divclk/clk_out` and monitor 1 on the new fixed clock. Monitor 1
sits on a clock of known frequency, so it calibrates the count-to-frequency
formula and turns monitor 0 into an absolute measurement.

The bridge counts, in the receiver's own domain, the clocks between two
accepted samples and the clocks the last joint search held the fabric, and
reports them on a third register page selected by `gp_ctrl[17]`.
`tools/read_clg400_symbol_trace.py` reads that page on every capture and puts
the numbers in the report under `receiver_clock`, with the SFD deadline
computed from the **measured** ratio. Scoring a search against the deadline the
design wants rather than the one it has is precisely how a fifty-nine-fold
overshoot came to look comfortable.

The page is read eight times and the largest interval kept, because
`util_wfifo` hands out samples in bursts of eight and a single reading can
legitimately land inside a burst.

### What this does and does not settle

A receiver clocked at 62.5 MHz makes the joint search *able* to finish inside
the SFD. It does not by itself establish that the search then produces a
correct estimate, that the `+1` bin bias disappears, or anything about link
quality. Those need the twelve-capture experiment re-run and the differential
ladder re-checked; the entry above records what was measured before the change,
and the result of the re-run belongs beside it.

## Evidence boundary

A successful result closes the symbol-decision defect and unblocks a PER
campaign. It does **not** establish packet error rate, sensitivity,
acquisition probability, timestamp repeatability, or calibrated ToA. Twelve
packets at one power level is a decision defect measurement, not a link
measurement, and must be reported as such.
