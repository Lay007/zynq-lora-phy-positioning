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

## Evidence boundary

A successful result closes the symbol-decision defect and unblocks a PER
campaign. It does **not** establish packet error rate, sensitivity,
acquisition probability, timestamp repeatability, or calibrated ToA. Twelve
packets at one power level is a decision defect measurement, not a link
measurement, and must be reported as such.
