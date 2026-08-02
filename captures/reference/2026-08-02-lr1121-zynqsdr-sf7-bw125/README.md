# LR1121 to ZynqSDR reference capture

This is the first curated over-the-air hardware capture in the project. A
LILYGO T3S3 LR1121 transmitted three counter packets; a ZynqSDR Z7020/AD9361
running Pluto-compatible firmware recorded one contiguous complex buffer.

- RF profile: 868.1 MHz, BW 125 kHz, SF7, CR 4/5, sync word `0x12`.
- Packet: explicit LoRa packet, 32-byte counter payload, CRC enabled, normal IQ.
- Transmission: three individually commanded packets at 0 dBm; the LR1121
  reported `state=0` and 84 ms duration for every packet.
- Recording: 1 MS/s, 4,194,304 samples, CF32 little-endian interleaved I/Q,
  manual RX gain 20 dB.
- Bench: OTA antennas were confirmed before transmission; antenna separation
  and absolute RF calibration were not recorded.

`iq.cf32` is stored with Git LFS. Its SHA-256 and complete machine-readable
provenance are in `manifest.json`. `inspection.png` is the MATLAB R2025a report.
The report shows all three bursts and estimates SF7, BW 125 kHz, CFO about
+185 Hz, and SNR about 53 dB.

This strong-signal recording validates the transmit/capture/inspection path. It
is not a calibrated sensitivity, BER, PER, EVM, or occupied-bandwidth result.
