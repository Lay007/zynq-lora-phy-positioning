# CLG400 symbol trace and payload session — 2026-09-03

This note records the frozen-symbol-trace image, its deployment, and the
over-the-air payload attempt that followed. It continues
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

## What this does and does not establish

Established: a real SX1262 packet transmitted over the air was received by the
ZynqSDR, frozen as PL symbol decisions, and decoded in software through the
explicit header, its checksum, the FEC, dewhitening, and the LoRa payload CRC,
yielding the exact bytes the transmitter built for that specific sequence number.

Not established: packet error rate, sensitivity, acquisition probability,
timestamp repeatability, or calibrated ToA. A one-in-ten payload rate at a strong
signal level is a measurement of the free-running grid, not of the link, and it
is not a PER figure. The next receiver step is to drive the correlator resync
inputs from the detector so the symbol grid aligns to the packet; the receiver
top already exposes `resync_valid`/`resync_skip` and the detector already
produces `chips_to_boundary`, and the overlay ties them off today.
