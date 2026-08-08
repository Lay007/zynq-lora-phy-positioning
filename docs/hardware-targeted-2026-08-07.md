# Targeted Heltec V4.3 hardware run, 7 August 2026

[Русская версия](ru/hardware-targeted-2026-08-07.md)

The fixed-geometry OTA run adds five Git LFS captures and 130 confirmed SX1262
transmissions. The complete dataset and reproducibility commands are in
[`captures/reference/2026-08-07-heltec-v43-zynqsdr-targeted`](../captures/reference/2026-08-07-heltec-v43-zynqsdr-targeted/README.md).

Key conclusions:

- the SF7/BW125 pre-check decoded 10/10 packets;
- the adaptive local-floor detector acquires 30/30 SF5 and 30/30 SF6 packets;
  matching payloads improve to 26/30 in both modes, with the remaining losses
  identified as header/CRC failures rather than missed activity;
- BW500 is usable when recaptured at Fs=4 MS/s: 10/10 packets decode, versus
  0/2 in the historical Fs=1 MS/s recording;
- the 50-packet SF7 run gives 18.50 us residual standard deviation after
  affine TX/RX clock fitting, but is not an absolute ToA calibration.

The next receiver work should therefore analyze low-SF symbol metrics, timing,
and residual CFO for the eight header/CRC failures, then validate the change
with controlled SNR sweeps. The next hardware timing step requires a safely
attenuated cable path and a timestamp closer to RF than the ESP32 millisecond
counter.
