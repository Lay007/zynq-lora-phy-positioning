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
errors and zero critical warnings (checkpoint checksum `ad4832b9`). With the
authoritative root clocks restored for checkpoint reporting, all timing
constraints are met: overall WNS is +0.433 ns and the active 62.5 MHz
`clk_div_sel_0_s` domain has +2.640 ns WNS. The structurally retained 125 MHz
leg has no setup endpoints.

The synthesized design uses 31,768 LUTs, 38,132 registers, 28 BRAM tiles and 84
DSPs; the 16K x 32 IQ history maps to 16 RAMB36 blocks. `TIMING-6`, `TIMING-7`
and `LUTAR-1` are absent from the final methodology report. The custom bridge
has no Critical CDC findings; its CDC-15 warnings describe the payload held
stable around the tested request/acknowledge mailbox. The concise evidence row
is in
[`docs/data/rtl-m4-clg400-board-synthesis.csv`](../../../docs/data/rtl-m4-clg400-board-synthesis.csv).
This is not yet post-route or live-board evidence.

## Recorded implementation gate

The complete design also places and routes successfully. All 54,993 routable
nets are fully routed, with exact post-route WNS +0.064 ns and WHS +0.031 ns.
The active 62.5 MHz domain is the setup limit at +0.064 ns; the unused 125 MHz
leg still has no setup endpoints. Bitgen and XSA export complete with zero
errors and zero critical warnings.

The generated files are ignored build products:

- `lora_receiver_clg400.runs/impl_1/system_top.bit` — 2,527,536 bytes,
  SHA-256 `8c39730d9f5d6f7732d0e143e010c2efebfd310d2f82454ad8656977e1a2cc17`;
- `lora_receiver_clg400.sdk/system_top.xsa` — 1,259,468 bytes,
  SHA-256 `e497c61f2756cd992da4b3f58e9bd92986c4eb29e458a045742f18a8c553acfb`.

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
| `0x79040404` | write | control: bit 0 enable, bit 1 stream reset, bits 15:8 sync word; zero sync word selects `0x12` |
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
