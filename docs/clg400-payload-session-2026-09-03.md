# CLG400 symbol trace and payload session — 2026-09-03/04

This note records the frozen-symbol-trace image, its deployment, the
over-the-air payload attempt that followed, and the receiver change that
attempt made necessary. It continues
[`clg400-hardware-session-2026-09-02.md`](clg400-hardware-session-2026-09-02.md),
which closed the single-packet timestamp path but produced no payload.

## What the image adds

The overlay gained a 128-entry frozen symbol trace behind a second gpreg page,
plus a pure-Python hard packet decoder on the host. The capture contract and the
register page are documented in
[`clg400-symbol-trace.md`](clg400-symbol-trace.md). Page zero keeps the
timestamp ABI unchanged, so the previous session's evidence stays valid.

## Build gate

Vivado 2021.1, `xc7z020clg400-2`, synthesis checkpoint checksum `d8b4dfb2`,
zero errors and zero critical warnings.

| Measurement | Result |
|---|---:|
| Post-synthesis WNS | +0.433 ns |
| Post-synthesis 62.5 MHz `clk_div_sel_0_s` WNS | +1.695 ns |
| Post-route WNS / TNS | +0.029 ns / 0.000 ns |
| Post-route WHS / THS | +0.020 ns / 0.000 ns |
| Setup/hold endpoints | 99,930 |
| Routable nets / fully routed / routing errors | 59,392 / 59,392 / 0 |
| Synthesized LUTs / registers | 34,652 / 40,115 |
| Implemented LUTs / registers | 32,007 / 39,408 |
| BRAM tiles / DSPs | 78 / 84 |
| IQ history / symbol trace RAMB36 | 64 / 2 |
| Routed DRC errors / critical warnings / warnings / advisories | 0 / 0 / 108 / 24 |

The first attempt at this image routed to a setup WNS of −0.003 ns and its
bitstream was discarded; only `system_top_bad_timing.xsa` remains from it. The
accepted run pins the router to `AggressiveExplore` and enables a post-route
physical optimization pass, which `build_bitstream.tcl` now does by default.

That accepted Vivado session was interrupted after `write_bitstream` and the
timing summary but before the platform export, which is why the run directory
held a valid bitstream and no XSA. Re-running implementation would have produced
a different route, so the platform was exported from the completed run instead
with `fpga/board/clg400/export_hw_platform.tcl`, which re-checks the run status
and re-runs the timing summary before writing:

- `system_top.bit` — 2,537,496 bytes,
  SHA-256 `86940ddba6fae4db7e49e5e0bb9447d78755a05d2388f38e70af7f0cfa6de148`;
- `system_top.xsa` — 1,334,646 bytes,
  SHA-256 `83a3f9f6fd6068e1782f6ce89cbba68144bbd56e762d6ca04730cb04e982683d`,
  containing exactly that bitstream.

The custom bridge has no Critical CDC findings. The whole-design CDC report still
lists Critical CDC-1 and CDC-13 rows, and all of them belong to the inherited ADI
DMA rather than to this overlay.

## Deployment

Only `/mnt/mmcblk0p1/system_top.bit` was replaced. QSPI, the boot loader, and the
FPGA manager were untouched, and no hot load was performed.

Read-only inspection first: `/dev/mmcblk0p1` mounted read-write with 58.6 MB
free, `fpga_manager` reporting `operating`, both `0x4C4F5241` signatures present,
and the active image checksummed as
`5a3d17991a4ae3c07c9836b5bb79234eae4bcf44bea346fad967364167cc4094`. That image
was copied to `system_top.bit.pre_symboltrace_20260903T194708Z` and verified
before anything was written. The new bitstream was streamed to a temporary file
on the same mount, checksum-compared against the local file, renamed atomically,
synced, and re-verified in place.

The board's SSH host key had changed since the previous session, and it changed
again across the cold boot that followed. Both times the connection was refused
rather than accepted silently, and the second change confirmed the explanation:
the board runs from a RAM disk, so its host keys are regenerated on every boot
and pinning one is only ever valid for the current power cycle. Each new key was
pinned in the ignored `fpga/build/clg400-board/known_hosts.current` only; the
user's system `known_hosts` was never modified.

## Why a free-running grid needs a quarter-symbol search

The overlay ties the correlator resync inputs low, so the FFT symbol grid never
realigns to a packet. Consecutive preamble upchirps are identical, so a window
straddling two of them stays a clean chirp and `preamble_bin` reports the grid
phase exactly. Payload symbols get no such help: the SFD is 2.25 downchirps, so
the payload boundaries sit a quarter symbol away from the preamble grid, and a
quarter symbol is exactly `2**(SF-2)` bins — 32 for SF7.

A model experiment settled this before the transmission. Building a complete
frame with the project CSS model, slicing it on a free-running grid at several
phases, and searching for the offset that reproduces the transmitted symbols
gives a constant −32 bins at every phase where one payload symbol dominates its
window. The trace decoder therefore searches three hypotheses — no adjustment
and ±a quarter symbol — each with a residual bin or two for integer CFO. Nothing
else about the raw decisions is scanned, and
`tests/test_lora_packet.py::test_free_running_grid_trace_decodes_the_golden_packet`
holds the whole chain to that.

The previous search covered ±2 bins only, so it could not have decoded a live
trace regardless of RF quality.

## Cold boot and radio profile

The board cold-booted the new image with `fpga_manager` reporting `operating`,
both `0x4C4F5241` signatures present, page zero unchanged at `0x00010000`, and
page one answering with the `0x53590000` symbol marker — an armed, empty trace.
`fpga/board/clg400/verify_board_b_cold_boot.sh` then passed with
`status=0x00011243`: receiver enabled in both domains, formatted RX activity
observed, no sticky overflow.

The AD9361 comes up at 30.72 MS/s after a power cycle and has to be returned to
the LoRa profile. The attribute order matters, and getting it wrong is what
`EINVAL` means here: the RX FIR cannot be enabled before the TX FIR is on and
the chain has been moved, so the working sequence is the one `ad9361_set_bb_rate`
uses — park at 3 MS/s with the FIR bypassed, load the 128-tap decimate- and
interpolate-by-4 filter, enable the TX FIR, set the target rate, and only then
enable the RX FIR. The profile then read back exactly as required:

```text
BBPLL:1024000000 ADC:32000000 R2:16000000 R1:8000000 RF:4000000 RXSAMP:1000000
```

with both FIR paths enabled, RX LO 868,099,998 Hz, RF bandwidth 200 kHz, and
manual 50 dB gain on both receive channels.

## Over-the-air payload result

Eleven individually commanded Heltec transmissions were used. Periodic
transmission was never started, every `send` was preceded and immediately
followed by `stop`, and the transmitter profile was verified before each one.
The transmitter defaults back to 0 dBm after its own power cycle, so the runner
sets and re-reads −9 dBm before transmitting. Ten of the eleven attempts
produced a saved trace; one attempt's trace read failed and that attempt is
counted, not hidden.

**The payload gate is closed.** In the attempt recorded at 20:09:50 UTC the
transmitter reported `TX seq=10 len=32 state=0 start_ms=2297116 duration_ms=83`,
and the trace frozen for that packet decoded to:

| Acceptance criterion | Result |
|---|---|
| Capture sequence increased | 11 → 12 |
| Trace complete, 128 entries | yes |
| Explicit header valid | yes |
| Header checksum valid | yes |
| Header fields | 32-byte payload, CR 4/5, payload CRC present |
| Payload CRC valid | yes |
| Payload signature | ASCII `ZLP1` |
| Payload sequence vs transmitter | 10 = 10 |

The decoded payload was
`5a4c50310a0000001c0d23000a0b0c0d0e0f101112131415161718191a1b1c1d`. Its
little-endian `start_ms` field is 2,297,116, which is exactly the `start_ms` the
transmitter printed for that same `send`, and the trailing counter bytes match
the value the firmware derives from sequence 10. Both are independent of the
CRC, so three separate checks agree on the same packet. The trace was frozen at
`preamble_bin` 20, the header started at trace entry 2, and the decoder used a
bin adjustment of −32 — the predicted quarter symbol.

The complete record, including the raw decisions of the accepted attempt, is in
[`data/clg400-symbol-trace-2026-09-03.json`](data/clg400-symbol-trace-2026-09-03.json),
and `tests/test_lora_packet.py` replays it as a regression.

## What the ten attempts say about the receiver

| Measurement | Result |
|---|---:|
| Saved attempts | 10 |
| Explicit header valid with a valid checksum | 10 / 10 |
| Payload CRC valid | 1 / 10 |
| Bin adjustment −32 / −33 | 8 / 2 |
| Header at trace entry 2 / entry 3 | 9 / 1 |

Header recovery is reliable; payload recovery is not, and the reason is
specific. Rebuilding the symbols the transmitter must have sent and diffing them
against a failing trace shows that **every wrong symbol is wrong by exactly +1
bin**, scattered through the packet rather than drifting along it. That is a
common sub-bin offset between the free-running FFT grid and the transmitter's
symbol grid, which no integer bin adjustment can remove.

The SF7 explicit header survives it because the header is always sent at reduced
rate: its decoder divides the bin by four, so a one-bin error is absorbed. The
payload is not sent at reduced rate, and CR 4/5 is a distance-2 code that detects
a single bit error without correcting it — and because the symbols are Gray
mapped, a +1 bin error is exactly one bit error. So a single affected symbol per
block is enough to lose the packet.

The residual is a property of the capture, not of the link: it depends on where
the packet lands relative to a grid that never realigns, which is why one attempt
in ten decoded cleanly at a strong signal level. Raising the transmit power would
not change it.

## What the payload result does and does not establish

Established: a real SX1262 packet transmitted over the air was received by the
ZynqSDR, frozen as PL symbol decisions, and decoded in software through the
explicit header, its checksum, the FEC, dewhitening, and the LoRa payload CRC,
yielding the exact bytes the transmitter built for that specific sequence number.

Not established: packet error rate, sensitivity, acquisition probability,
timestamp repeatability, or calibrated ToA. A one-in-ten payload rate at a strong
signal level is a measurement of the free-running grid, not of the link, and it
is not a PER figure.

## Aligning the symbol grid

The port for the fix had been in the design from the start, tied to zero. The
generated correlator does not just accept `resyncValid`/`resyncSkip`; it states
the mechanism and where the decision belongs:

> Realignment works by dropping samples, not by loading a phase… Mechanism, not
> policy. Choosing s belongs to the front-end that owns the detector; for a
> preamble at bin d the required advance is `chipsToBoundary*L = mod(-d, N)*L`.

That formula lands the grid on the **preamble** boundary. The payload does not
start there: the 2.25-downchirp SFD puts it a further quarter symbol on, so the
advance is `mod(chipsToBoundary + 2**(SF-2), 2**SF)` chips. For the accepted
capture, with preamble bin 20 and `chipsToBoundary` 108, that is
`mod(140, 128) = 12` chips rather than 140 — the grid repeats every 128 chips,
so the short advance is equivalent and cheaper. Writing 140 into the unit test
was the first thing tried, and the test rejected it.

Three details decided the implementation.

The request is raised on `detected`, not on the earlier `preambleDetected`. The
generated detector deliberately decides the preamble early, on the newest eight
bins, and says why: so that a grid realignment derived from it can take effect
before the sync word has gone past. But its sync check compares the sync symbols
against `reference = history[0]`, a preamble bin captured on the old grid. Moving
the grid in between would compare bins measured on two different grids, and the
packet would stop being detected at all. Waiting costs nothing: the advance is
under one and a quarter symbols and the SFD still has 2.25 symbols to run.

The request has to be held. The correlator only latches it on an accepted
sample, and at 1 MS/s against a 62.5 MHz clock roughly one clock in sixty is an
accepted sample, so a single-cycle pulse would simply never be seen. It is held
until one accepted sample has passed and then dropped, because holding longer
would let a second window of the same packet take it again. One realignment per
armed capture, re-armed by a receive-stream reset.

The ToA path is untouched. The IQ history and the 64-bit sample counter are both
written before the withholding, so no holes appear in either and the monotonic
count TDoA depends on is preserved. The complete receiver regression reproduces
the same timestamp and fractional ToA with the aligner active.

## The double subtraction the fix would have caused

Aligning the grid changes what software must do, and missing that would have
broken decoding with the very change that fixes it. On a realigned grid the raw
decisions are the transmitted symbols: the advance removes the grid phase and,
with it, the integer part of any carrier offset, which an upchirp-only
measurement cannot distinguish from timing in the first place. Subtracting the
measured `preamble_bin` again would remove it twice.

So the trace page reports it. `DEBUG` bit 8 is set once the receiver has
realigned for that capture, the reader removes the measured bin only when the
receiver did not, and the saved report records which value it used as
`grid_phase_removed`. The flag also separates "the aligner never fired" from
"it fired and the arithmetic is wrong" — indistinguishable from a decoded trace
alone, and each round trip here costs a rebuild and a cold boot.

## What the model predicts

Rebuilding a frame with the project CSS model, slicing it on a free-running grid
across a sweep of arrival phases, and repeating with the realigned grid:

| Fractional CFO | Clean packets, free-running grid | Clean packets, realigned grid |
|---:|---:|---:|
| 0.00 bins | 79 % | 99 % |
| 0.25 bins | 50 % | 99 % |
| 0.45 bins | 17 % | 100 % |
| 3.40 bins | 28 % | 96 % |
| 8.60 bins | 63 % | 92 % |

The 0.45-bin row is the one that matches the board: 17 % predicted against
1 payload in 10 measured. The model has no noise and no sampling-frequency
offset, so the agreement is qualitative, not a forecast.

`tests/test_lora_packet.py` pins both halves of the change: one case decodes a
free-running-grid trace and requires the −32 adjustment, the other decodes a
realigned-grid trace with a grid phase of zero and requires no adjustment at
all. `fpga/tb/tb_lora_symbol_grid_resync.sv` covers the advance arithmetic, the
wrap, the hold across a sparse sample stream, and the one-shot behaviour.

## What the realigned build actually did

The image built, routed to +0.031 ns post-route WNS and +0.035 ns WHS over
100,045 endpoints with all 59,523 routable nets fully routed and no routing
errors, and cold-booted. Synthesis added 51 registers, which is exactly the
aligner's state: armed, request, a 16-bit held advance, a 32-bit held skip, and
the two synchroniser stages for the status flag.

On the board the change does what it claims, and the trace says so directly.
Across sixteen saved captures:

| Measurement | Result |
|---|---:|
| Captures with the grid realigned (`DEBUG` bit 8) | 16 / 16 |
| Captures decoded with no bin adjustment | 16 / 16 |
| Explicit header valid with a valid checksum | 16 / 16 |
| Payload CRC valid | 3 / 16 |

The quarter symbol is gone: every capture now decodes at `bin_adjustment` 0
where the previous build needed −32, and the header moved from trace entry 2 or
3 to entry 1 or 2, which is the skip showing up in the capture window.

**The payload rate did not improve the way the model predicted.** Three captures
in sixteen against one in ten before is not a distinguishable difference at
these sample sizes, and it is nowhere near the ~100 % the noiseless model
suggested. The prediction was wrong, and the reason is worth more than the
prediction was.

## The residual is one-sided, and alignment cannot reach it

Rebuilding the transmitted symbols and diffing them against the realigned
captures shows the errors survived the change and kept their shape: of 204 wrong
symbols across thirteen captures, **190 are exactly +1 bin and not one is −1**.
A one-sided sub-bin bias is left after the grid has been moved by a whole number
of chips, and no integer advance can remove it. So the 75 %/25 % window straddle
was not the dominant cause after all; a fractional offset was, and the quarter
symbol was simply sitting on top of it.

One shortcut was measured and rejected. A +1 symbol error is exactly one Gray
bit flip, which lands in exactly one CR 4/5 codeword and shows up there as odd
parity, and the bias is one-sided — so each symbol in a block is either as read
or one lower, 32 hypotheses per five-symbol block. Run against these same
captures it lifted 2 of 13 to 4 of 13. That is not a fix: a distance-2 code
cannot tell a clean block from one with two tipped symbols, so beyond the
easiest cases the search would be guessing, and the payload CRC would be the
only thing standing between a guess and a wrong packet reported as good.

The honest next step is to estimate the fractional offset rather than guess it.
The material is already there: the model layer has `joint_timing_cfo_from_bins`
and soft-decision decoding, and the trace already carries a per-symbol
confidence that a hard decision throws away.

## Where the receiver stands now

Established on hardware: a real over-the-air SX1262 packet decoded end to end
through header checksum, FEC, dewhitening and payload CRC to the exact bytes the
transmitter built, on both the free-running and the realigned build; and a
symbol grid that the receiver aligns to the packet it acquired, verified by a
flag the PL sets and by the bin adjustment the decoder no longer needs.

Not established: packet error rate, sensitivity, acquisition probability,
timestamp repeatability, or calibrated ToA. Three payloads in sixteen at a
strong signal level measures a sub-bin decision defect, not a link.
