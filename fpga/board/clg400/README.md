# CLG400 board overlay

This directory composes the portable SF7/L=8 timestamp receiver with the
hardware-qualified AD9361 shell recovered in the sibling `zynq-sdr-course`
checkout. It creates a separate project under `fpga/build/clg400-board`; the
course project and its deployed artifacts are read-only inputs.

## Build inputs

- Vivado 2021.1.
- This repository and `zynq-sdr-course` checked out as sibling directories, or
  `ZYNQ_SDR_COURSE_ROOT` set to the latter.
- The generated, namespaced HDL snapshots committed under `fpga/generated`.
- `fpga/rom/lora_sf7_l8_reference_q10.mem`.

Create the project:

```powershell
& G:\Xilinx\Vivado\2021.1\bin\vivado.bat -mode batch -nojournal -nolog `
  -source fpga\board\clg400\system_project.tcl
```

Run the synthesis evidence gate before implementation:

```powershell
& G:\Xilinx\Vivado\2021.1\bin\vivado.bat -mode batch -nojournal -nolog `
  -source fpga\board\clg400\synth_board.tcl
```

The reports are written under the ignored
`fpga/build/clg400-board/reports` directory.

If Windows Vivado finishes `synth_design` and writes `system_top.dcp` but its
run launcher does not return, do not repeat synthesis. After confirming the log
contains `0 Errors` and the completion marker exists, generate the same reports
directly from the checkpoint:

```powershell
& G:\\Xilinx\\Vivado\\2021.1\\bin\\vivado.bat -mode batch -nojournal -nolog `
  -source fpga\\board\\clg400\\report_board_checkpoint.tcl
```

Build implementation and bitstream only after project creation succeeds:

```powershell
& G:\Xilinx\Vivado\2021.1\bin\vivado.bat -mode batch -nojournal -nolog `
  -source fpga\board\clg400\build_bitstream.tcl
```

The target is exactly `xc7z020clg400-2`. The overlay keeps the vendor RX/TX DMA
paths intact and taps the formatted RX1 FIFO stream. It does not connect to raw
offset-binary ADC pins and does not replace the vendor DAC path. This low-rate
image pins the shared ADI `util_clkdiv` selector to its divide-by-four leg:
62.5 MHz at the shell's 250 MHz worst-case input constraint. The divide-by-two
125 MHz mode is deliberately unsupported because the current generated FFT does
not meet that clock. The required radio/sample configuration is 1 Msps.

## Recorded synthesis gate

The complete `system_top` synthesis for `xc7z020clg400-2` completed with zero
errors and zero critical warnings (checkpoint checksum `d8b4dfb2`). With the
authoritative root clocks restored for checkpoint reporting, all timing
constraints are met: overall WNS is +0.433 ns and the active 62.5 MHz
`clk_div_sel_0_s` domain has +1.695 ns WNS. The structurally retained 125 MHz
leg has no setup endpoints.

The synthesized design uses 34,652 LUTs, 40,115 registers, 78 BRAM tiles and 84
DSPs; the 64K x 32 IQ history maps to 64 RAMB36 blocks and the 128 x 128-bit
symbol trace adds exactly 2 more. `TIMING-6`, `TIMING-7` and `LUTAR-1` are
absent from the final methodology report. The custom bridge has no Critical CDC
findings; its CDC-3/CDC-6 entries are the declared `ASYNC_REG` synchronizers of
the status, debug, and trace-state words. The Critical CDC-1/CDC-13 rows in the
whole-design report all belong to the inherited ADI DMA and are not part of this
bridge. The concise evidence row is in
[`docs/data/rtl-m4-clg400-board-synthesis.csv`](../../../docs/data/rtl-m4-clg400-board-synthesis.csv).
This is not yet post-route or live-board evidence.

## Recorded implementation gate

The complete design also places and routes successfully. All 59,392 routable
nets are fully routed, with exact post-route WNS +0.029 ns and WHS +0.020 ns
over 99,930 setup/hold endpoints and zero total violation. The active 62.5 MHz
domain is the setup limit at +0.029 ns; the unused 125 MHz leg still has no
setup endpoints. This margin is small enough that `build_bitstream.tcl` pins the
router to `AggressiveExplore` and runs a post-route physical optimization pass
before the bitstream is accepted. Bitgen and XSA export complete with zero
errors and zero critical warnings.

The implemented design uses 32,007 LUTs, 39,408 registers, 78 BRAM tiles and 84
DSPs. The generated files are ignored build products:

- `lora_receiver_clg400.runs/impl_1/system_top.bit` — 2,537,496 bytes,
  SHA-256 `86940ddba6fae4db7e49e5e0bb9447d78755a05d2388f38e70af7f0cfa6de148`;
- `lora_receiver_clg400.sdk/system_top.xsa` — 1,334,646 bytes,
  SHA-256 `83a3f9f6fd6068e1782f6ce89cbba68144bbd56e762d6ca04730cb04e982683d`.

If a Vivado session is interrupted after `write_bitstream` but before the XSA is
written, do not re-run implementation: a fresh route would change the artifact
that was already signed off. Export the platform from the completed run instead,
which re-checks the run status and the timing summary first:

```powershell
& G:\Xilinx\Vivado\2021.1\bin\vivado.bat -mode batch -nojournal -nolog `
  -source fpga\board\clg400\export_hw_platform.tcl
```

The routed DRC contains no errors, but retains warnings from the inherited ADI
shell and generated DSP: asynchronous-reset checks on BRAM controls and
pipeline recommendations for DSP48 cells. The complete development boot set is
now packaged and checksum-verified offline, but it is not qualified firmware
until it has been cold-booted. The concise implementation record is
[`docs/data/rtl-m4-clg400-board-implementation.csv`](../../../docs/data/rtl-m4-clg400-board-implementation.csv).

## PS control plane

The overlay extends the existing AXI interconnect with `axi_gpreg_lora` at
`0x79040000`. Its core ID and bridge signature are both `0x4c4f5241` (`LORA`).

| Address | Direction | Meaning |
|---|---|---|
| `0x79040000` | read | `axi_gpreg` version |
| `0x79040004` | read | core ID, `0x4c4f5241` |
| `0x79040404` | read/write | control: bit 0 enable, bit 1 stream reset, bits 15:8 sync word; bit 16 selects the symbol page; bits 30:24 select its trace entry; zero sync word selects `0x12` |
| `0x79040408` | read | status/build word |
| `0x79040448` | read | accepted metadata sequence |
| `0x79040488` | read | coarse timestamp `[31:0]` |
| `0x790404c8` | read | coarse timestamp `[63:32]` |
| `0x79040508` | read | signed fractional ToA Q12 |
| `0x79040548` | read | signed log peak Q12 |
| `0x79040588` | read | sticky receiver-stage/error diagnostics and packet-start count low word |
| `0x790405c8` | read | bridge signature, `0x4c4f5241` |

Status bits are:

- bit 0: enable requested in the PS domain;
- bit 1: enable observed in the sample domain;
- bit 2: at least one atomic metadata snapshot accepted;
- bit 3: sticky metadata/mailbox overflow;
- bit 4: ToA search busy;
- bit 5: packet start seen since stream reset;
- bit 6: valid formatted sample seen since stream reset;
- bit 7: stream reset requested;
- bits 15:8: requested sync word;
- bits 31:16: bridge build version (`0x0001`).

Read `SEQUENCE`, then all timestamp words, then `SEQUENCE` again; retry if the
two sequence reads differ. The board bridge transfers all timestamp fields as
one request/acknowledge mailbox entry, and status bit 3 reports an event that
arrived before the prior one was acknowledged.

Control bit 16 selects a second, read-only view of the same gpreg outputs. It
exposes a frozen 128-entry post-acquisition symbol trace without changing the
timestamp page-zero ABI. Bits 30:24 select the entry. On this page `STATUS`
contains the `0x5359` (`SY`) marker, complete/active flags in bits 9:8, and the
captured count in bits 7:0; `SEQUENCE` is the trace sequence; the next three
words contain the raw symbol and 64-bit sample count; `LOG_PEAK` contains trace
flags and confidence; and `DEBUG` contains the preamble bin, selected index,
and count. A complete trace reports `STATUS=0x53590280`. The full capture and
software-decoder contract is documented in
[`docs/clg400-symbol-trace.md`](../../../docs/clg400-symbol-trace.md).

This page carried the first decoded over-the-air LoRa payload on this
board: a Heltec packet whose frozen trace passed the explicit-header
checksum and the LoRa payload CRC and returned the transmitted sequence
number. The run is recorded in
[`docs/clg400-payload-session-2026-09-03.md`](../../../docs/clg400-payload-session-2026-09-03.md).

`DEBUG` is cleared by stream reset. Bits 15:0 capture
`packet_start_count[15:0]` on the latest acquisition, bit 16 is the internal
receiver-enable state, and bits 17, 18, 19, 20, and 21 respectively indicate
that metadata, fractional ToA, peak triplet, matched-filter correlation, and
ToA-search stages were reached. Bits 31:22 are sticky errors in this order:
alignment, symbol-index width,
search underflow, search restart, MAC window mismatch, MAC read miss, MAC
response mismatch, MAC restart, peak-at-boundary, and peak restart.

## Package the board-B SD directory

After implementation, assemble the six-file SD payload and its manifest:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  fpga\board\clg400\package_board_b_boot_set.ps1
```

The script validates fixed SHA-256 values for the deployed board-B baseline,
the course kernel, the new bitstream, and the XSA. It refuses to overwrite an
existing output and creates the ignored directory
`fpga/build/clg400-board/boot-set-board-b`. The archived board-B artifact set
omitted `uImage`; the selected sibling-course copy is byte-identical to the
original deployed source. `manifest.json` explicitly marks the result
unqualified and offline-only. The tracked six-row evidence record is
[`docs/data/rtl-m4-clg400-board-boot-package.csv`](../../../docs/data/rtl-m4-clg400-board-boot-package.csv).

After the first cold boot, copy `verify_board_b_cold_boot.sh` to `/tmp` on the
board and run it as root. It checks the two `LORA` identity words, performs a
receiver-only reset/enable, verifies formatted RX activity and overflow, and
reads an atomic metadata snapshot. It does not touch FPGA manager, QSPI, or TX
controls.

## Deployment boundary

Project creation, synthesis, implementation, and bitstream generation are
separate evidence gates. A generated `.bit` must not be hot-loaded into the
running course Linux image: earlier hardware work demonstrated that this can
leave RX DMA unusable while the gpreg window still responds. Copy the prepared
six-file boot set to a cloned SD card, verify checksums, and cold-boot it by the
procedure in `docs/clg400-hardware-bring-up.md`.
