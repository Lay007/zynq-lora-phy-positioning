# CLG400 frozen symbol trace and hard packet decoder

The CLG400 overlay can freeze 128 consecutive FFT symbol decisions after a
packet acquisition. This is the smallest useful observability layer between
the on-board LoRa detector and the software packet decoder: it preserves the
existing timestamp snapshot ABI and does not add a DMA path or a second packet
receiver in PL.

```text
AD9361 RX1 -> FFT decisions -> blind detector -> timestamp/ToA path
                         |
                         +-> 128-entry frozen BRAM -> gpreg page 1
                                                        |
                                                        v
                                             Python hard decoder
                                             header -> FEC -> CRC
```

This path is RX-only. It does not control the AD9361 transmitter, FPGA manager,
boot flash, or QSPI.

## Capture contract

The detector pulse is aligned with the second sync-word decision. The trace
starts at the next valid decision, so the expected SF7 layout is:

| Trace entry | Expected decision |
|---:|---|
| 0 | first full SFD downchirp |
| 1 | second full SFD downchirp |
| 2 | first explicit-header symbol |
| 3... | remaining header and payload symbols |

The buffer keeps accepting decisions after the RF packet ends until all 128
entries are present. This gives software a simple frozen-buffer contract; the
decoded header determines the exact packet length and trailing decisions are
ignored. A receive-stream reset re-arms the buffer. The capture sequence is
incremented only after the complete 128-entry trace has frozen.

Each entry stores the 32-bit raw FFT symbol index, the aligned 64-bit sample
counter, 16-bit confidence, and two flags (`timestamp_valid` and
`packet_detected`). The common preamble bin is captured with the detector event.
Software reads the dual-clock RAM only after `capture_complete`, when its write
port has stopped.

## PS register page

The original eight-register gpreg window remains at `0x79040000`. Timestamp
page 0 is unchanged. Set control bit 16 to select the symbol page and control
bits 30:24 to select one of its 128 entries.

| Existing gpreg output | Symbol-page meaning |
|---|---|
| `STATUS` | `0x5359` marker in bits 31:16; complete, active, and count in bits 9, 8, and 7:0 |
| `SEQUENCE` | completed trace sequence |
| `COARSE_LO` | selected raw symbol index |
| `COARSE_HI` | selected sample count bits 31:0 |
| `FRACTIONAL` | selected sample count bits 63:32 |
| `LOG_PEAK` | flags in bits 23:16 and confidence in bits 15:0 |
| `DEBUG` | preamble bin in bits 31:16, selected index in bits 15:9, captured count in bits 7:0 |
| `SIGNATURE` | unchanged `0x4c4f5241` (`LORA`) |

A complete 128-entry trace therefore reports status `0x53590280`. Software
must restore the original control word after reading the page.

## Read and decode

Make the local package importable and re-arm the RX trace before transmitting
one packet:

```powershell
$env:PYTHONPATH = (Resolve-Path src).Path
python tools/read_clg400_symbol_trace.py --host 192.168.40.1 --arm
```

Key authentication is used by default. For a Pluto-style password login, keep
the password out of the command line and pin the current board host key:

```powershell
$env:CLG400_SSH_PASSWORD = [System.Net.NetworkCredential]::new(
  '', (Read-Host -AsSecureString 'CLG400 SSH password')).Password
python tools/read_clg400_symbol_trace.py --host 192.168.40.1 `
  --password-env CLG400_SSH_PASSWORD --known-hosts .\known_hosts.board --arm
```

Do not silently replace a changed host key in the user's system
`known_hosts`; verify and pin the board key separately.

After a single Heltec `send` and at least 0.2 seconds of capture time, read and
save the frozen trace:

```powershell
python tools/read_clg400_symbol_trace.py --host 192.168.40.1 `
  --output experiments/runs/clg400-symbol-trace.json
```

The reader uses one SSH session, verifies the `LORA` signature and `SY` page
marker, rejects active or changing captures, restores the original control
word, then invokes the pure-Python hard decoder. The decoder mirrors the
authoritative MATLAB Gray mapping, diagonal deinterleaving, Hamming coding,
explicit-header checksum, whitening, and LoRa payload CRC.

## One-shot acceptance run

Arming, transmitting, and reading by hand invites two mistakes that quietly
invalidate the evidence: a transmitter left running periodically, and a trace
that some earlier packet had already frozen. `tools/run_clg400_payload_capture.py`
performs the whole attempt as one operation -- arm, stop the transmitter, check
its firmware and profile, send exactly once, stop again, then read and decode
the trace -- and writes the serial log and the trace JSON side by side:

```powershell
$env:PYTHONPATH = (Resolve-Path src).Path
python tools/run_clg400_payload_capture.py `
  --host 192.168.40.1 --password-env CLG400_SSH_PASSWORD `
  --known-hosts fpga/build/clg400-board/known_hosts.current `
  --port COM10 --run-dir experiments/runs/clg400-payload
```

It never issues `start`, and it exits non-zero unless the payload CRC is valid
and the decoded `ZLP1` sequence equals the sequence the transmitter reported for
that one `send`.

## Why the payload sits a quarter symbol off the grid

The overlay ties the correlator `resyncValid`/`resyncSkip` inputs low, so the
FFT symbol grid never realigns to a packet: it stays wherever the receive
stream started. That is deliberate — the trace is an observability tap, not a
second receiver — but it decides how software has to read the decisions.

Consecutive preamble upchirps are identical, so a window straddling two of them
is still a clean chirp and the common `preamble_bin` reports exactly the grid
phase. Payload symbols do not get that for free. The SFD is 2.25 downchirps, so
the payload symbol boundaries sit a quarter symbol away from the grid the
preamble established, and a quarter symbol is exactly `2**(SF-2)` bins: 32 for
SF7. Every payload decision therefore carries a constant bin offset on top of
`preamble_bin`, and each window mixes about 75 % of one payload symbol with
25 % of its neighbour.

The trace decoder searches exactly that hypothesis set: no adjustment, minus a
quarter symbol, plus a quarter symbol, each with a residual bin or two for
integer CFO, combined with the few plausible SFD-to-header offsets. Nothing
else about the raw decisions is scanned. `quarter_symbol_bin_adjustments`
builds the list, and `tests/test_lora_packet.py` proves the need for it by
rebuilding a complete frame with the project CSS model, slicing it on a
free-running grid at several phases, and decoding the result end to end.

The current decoder consumes hard decisions only. A failed CRC can therefore
mean an RF/synchronization error even when the packet detector and timestamp
path succeeded. It is not evidence that the transmitter sent a bad payload;
the retained raw entries, confidence values, and sample counters are the input
to the next synchronization or soft-decision iteration.

## Acceptance boundary

A Heltec-to-ZynqSDR payload is confirmed only when all of the following hold in
the same saved run:

1. the trace sequence increments and the buffer freezes with 128 entries;
2. the explicit header fields and header checksum are valid;
3. the payload CRC is valid;
4. the decoded `ZLP1` sequence matches the Heltec serial log for that send.

RTL and Python golden-vector regressions verify implementation behavior but do
not replace this over-the-air acceptance check.

That check passed on 2026-09-03. The accepted attempt froze 128 entries at
`preamble_bin` 20, started the header at entry 2, needed a −32 bin adjustment,
and decoded to `ZLP1` with sequence 10 — the sequence the transmitter reported
for that single `send` — through a valid header checksum and a valid payload
CRC. The raw decisions of that capture are committed as
[`data/clg400-symbol-trace-2026-09-03.json`](data/clg400-symbol-trace-2026-09-03.json)
and replayed by `tests/test_lora_packet.py`.

Across ten saved attempts the header and its checksum were valid every time and
the payload CRC once. Rebuilding the transmitted symbols and diffing them against
a failing trace shows why: every wrong symbol is wrong by exactly +1 bin,
scattered rather than drifting, which is a common sub-bin offset between the
free-running grid and the transmitter. The SF7 header absorbs it because it is
sent at reduced rate and its decoder divides the bin by four; the payload is not,
and a Gray-mapped +1 bin error is a single bit error that CR 4/5 detects but
cannot correct. Closing that gap means aligning the grid in PL —
`resync_valid`/`resync_skip` on the receiver top and `chips_to_boundary` from the
detector exist for exactly this and are tied off today — not raising transmit
power.
