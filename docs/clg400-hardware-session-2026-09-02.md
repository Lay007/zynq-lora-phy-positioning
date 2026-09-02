# CLG400 board B cold boot and first OTA acquisition — 2026-09-02

This note records the first successful cold boot of the project image and the
first over-the-air acquisition on board B. It is acquisition evidence only: the
real packet did not yet produce a software-visible metadata sequence or ToA.

## Hardware and RF profile

- Receiver: CLG400 ZynqSDR board B, Zynq-7020 and AD9361, RX1 antenna input.
- Transmitter: Heltec WiFi LoRa 32 V4.3, ESP32-S3 and SX1262, antenna output.
- Link: over the air, with both antennas fitted.
- Heltec profile: 868.100 MHz, BW 125 kHz, SF7, CR 4/5, sync word `0x12`,
  preamble 12, CRC on, normal IQ, −9 dBm, 32-byte counter payload.
- Safety: only single `send` operations were used; periodic transmission was
  stopped. QSPI was not modified.

## Cold-boot result

The original SD contents were backed up before installing the development boot
set. After a full power cycle:

- Linux booted and the FPGA manager reported `operating`;
- `devmem 0x79040004 32` and `devmem 0x790405c8 32` both returned
  `0x4C4F5241` (`LORA`);
- the AD9361 driver probed successfully;
- `fpga/board/clg400/verify_board_b_cold_boot.sh` passed the gpreg signature,
  IIO, formatted RX sample activity, and overflow checks;
- RX DMA remained usable.

The AD9361 could not reach 1 MS/s with its initial filter chain. Loading the
standard 128-tap FIR with decimation/interpolation 4 and enabling both RX and TX
FIR attributes allowed exact 1 MS/s operation. The confirmed RX chain was:

```text
BBPLL:1024000000 ADC:32000000 R2:16000000 R1:8000000 RF:4000000 RXSAMP:1000000
```

The RX LO read back as 868,099,998 Hz and the RF bandwidth was 200 kHz. Manual
RX gain was set to 50 dB on both channels for the acquisition test.

## First OTA observation

Before transmission the receiver status was `0x00011243`. A single Heltec
packet changed it to `0x00011263`: the sticky packet-start bit asserted while
sample activity remained present. The AXI metadata sequence stayed at zero.
Resetting the stream and repeating one packet reproduced the same result.

A synchronized RX DMA capture confirmed that the RF packet reached RX1:

| Measurement | Result |
|---|---:|
| RX1 median power | 2.9 |
| RX1 peak power | 1196.8 |
| Energy edge | sample 42,743 |
| Matched-filter peak | sample 42,940 |
| Peak minus energy edge | +197 samples |
| Matched-filter peak/median | 3386 |
| Dechirped FFT concentration at the matched peak | 0.9766 |

The best match used the normal, not conjugated, ideal reference. This confirms
the expected RX1 IQ orientation. At the energy edge the dechirped slope was
about −16.9 kHz and the FFT peak was around −24.4 kHz; at the matched-filter
peak the slope was about −56.9 Hz and the peak was in bin zero.

## Open gate

The failure is downstream of RF acquisition: packet-start is reached but the
metadata snapshot is not. The next bitstream exposes the last reached receiver
stages and sticky abort causes in `gp_debug`. After a cold boot, one packet is
enough to distinguish detector/search, matched-filter, peak-boundary, metadata,
and CDC-mailbox failures. Only after metadata is restored should the controlled
cable run of 1,000 packets begin.

The diagnostic build completed in Vivado 2021.1 with all timing constraints
met: WNS +0.052 ns, WHS +0.033 ns, zero unrouted nets, zero implementation
errors, and zero critical warnings. The 2,511,068-byte bitstream has SHA-256
`f7a83357637580d7f049323fde5fd1c7813015a7056a4345e6099a48e3d0faa6`.
It was copied to `/mnt/mmcblk0p1/system_top.bit` and verified there; the prior
bitstream is retained as `system_top.bit.pre_diag_20260902T0718Z` with SHA-256
`8c39730d9f5d6f7732d0e143e010c2efebfd310d2f82454ad8656977e1a2cc17`.
The diagnostic image became active after the next full power cycle. Its idle
value was `gp_debug=0x00010000`, confirming that the new map and internal
receiver enable were live.

## Diagnostic result and root cause

With the same 1 MS/s RF profile, one packet changed `gp_debug` to
`0x0431ec00`. Decoding the sticky bits showed:

- packet start count low word `0xec00`;
- ToA search reached;
- at least one matched-filter correlation completed;
- no peak triplet, fractional ToA, or metadata event;
- `toa_mac_read_miss_error` asserted.

Two reset-to-transmit measurements separated by 0.20 seconds changed the
detected packet-start low word by `0x0c00` modulo 65,536. Accounting for three
counter wraps gives about 998.4 ksample/s, consistent with the configured
1 MS/s stream rather than a continuous 62.5 MHz valid signal.

The full-size matched-filter regression previously stopped writes before
starting the 17-lag search. After changing it to preload 11,264 samples and
continue accepting one sample every clock during the search, the 16,384-sample
history reproduced the board failure: only 3 of 17 correlations completed,
then `read_miss` aborted the search and no triplet was produced. A 65,536-sample
history passes the same live-history golden-vector test, the complete packet
ToA receiver test, and the CLG400 bridge test.

The enlarged-history full-board build also passed implementation sign-off. It
uses 30,312 slice LUTs, 37,595 slice registers, 76 of 140 BRAM tiles, and 84
DSPs. All 56,263 routable nets are fully routed with zero routing errors;
post-route WNS is +0.211 ns and WHS is +0.033 ns. The 2,535,616-byte bitstream
has SHA-256
`5a3d17991a4ae3c07c9836b5bb79234eae4bcf44bea346fad967364167cc4094`.
It was copied and checksum-verified as `/mnt/mmcblk0p1/system_top.bit`; the
active diagnostic image was retained as
`system_top.bit.pre_history65k_20260902T120400Z`. A cold-boot hardware retest
was still required before the fix could be called verified on board.

## Enlarged-history cold-boot result

The board cold-booted the enlarged-history image with FPGA manager state
`operating`, both `LORA` signatures present, and the expected idle
`gp_debug=0x00010000`. The AD9361 profile was restored and read back as RX/TX
1 MS/s, both FIR paths enabled, RX LO 868,099,998 Hz, RX bandwidth 200 kHz,
and manual 50 dB gain on both receive channels. The receiver-only cold-boot
smoke test passed with `status=0x00011243` and no overflow.

Three individually commanded Heltec packets were used; periodic transmission
was never started and every `send` was followed immediately by `stop`:

- the first packet was not acquired and left `gp_debug=0x00010000`;
- the second reached all correlations without `read_miss`, then reported
  `peak_at_boundary_error` as `gp_debug=0x00b12800`;
- the third completed the complete timestamp path with
  `status=0x00011267`, `gp_debug=0x003f7c00`, and sequence `1`.

The accepted metadata snapshot for the third packet was coarse timestamp
`0x00000000000f7bfc` (1,014,780 accepted samples), fractional ToA `0x42b`
(+0.260498 sample in Q12), and log-peak word `0x0000e9b8`. Debug bits 16
through 21 were all set and bits 31 through 22 were all clear: metadata,
fractional ToA, peak triplet, correlation, and search were reached with no
sticky abort cause. This closes the single-packet hardware-connectivity gate
for the enlarged history. It does not yet establish acquisition probability,
timestamp repeatability, calibrated delay, PER, or sensitivity; those require
the controlled cable run.
