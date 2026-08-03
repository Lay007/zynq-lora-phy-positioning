# LR1121 to ZynqSDR hardware sweep, 2 August 2026

[Русская версия](ru/hardware-sweep-2026-08-02.md)

The validated OTA sweep contains 27 LoRa modes, 70 transmitter-confirmed
packets, and 469,762,048 bytes (448 MiB) of CF32 IQ. It covers SF5–SF12,
BW 62.5–500 kHz, CR 4/5–4/8, four output-power settings, five payload lengths,
four preamble lengths, CRC off, sync word `0x34`, and inverted IQ.

The source experiments remain under ignored `artifacts/phy-sweeps/`. The 27
validated captures and their manifest are promoted to
`captures/reference/2026-08-02-lr1121-zynqsdr-mode-sweep/`, with IQ stored by
Git LFS. Failed diagnostics and duplicate repair runs are not published.

Use `tools/run_phy_sweep.py` to acquire the matrix,
`tools/analyze_phy_sweep.py` to run profile-constrained MATLAB reports, and
`tools/curate_phy_sweep.py` to verify SHA-256 and create the reference dataset.
The complete procedure, limitations, Heltec backup provenance, and next BER
step are documented in the [Russian report](ru/hardware-sweep-2026-08-02.md).

The subsequently completed Heltec V4.3/SX1262 capture matrix is documented in
the [3 August hardware report](hardware-sweep-2026-08-03-heltec-v43.md).
