# Targeted Heltec V4.3 hardware run, 7 August 2026

[Русская версия](ru/hardware-targeted-2026-08-07.md)

The fixed-geometry OTA run adds five Git LFS captures and 130 confirmed SX1262
transmissions. The complete dataset and reproducibility commands are in
[`captures/reference/2026-08-07-heltec-v43-zynqsdr-targeted`](../captures/reference/2026-08-07-heltec-v43-zynqsdr-targeted/README.md).

Key conclusions:

- the SF7/BW125 pre-check decoded 10/10 packets;
- the adaptive local-floor detector acquires 30/30 SF5 and 30/30 SF6 packets;
  polyphase FFT-power combining raises exact payload matches to 30/30 in both
  modes by using all eight oversampling phases;
- BW500 is usable when recaptured at Fs=4 MS/s: 10/10 packets decode, versus
  0/2 in the historical Fs=1 MS/s recording;
- the 50-packet SF7 run gives 18.72 us residual standard deviation after
  affine TX/RX clock fitting, but is not an absolute ToA calibration.

All 130 recorded payloads now match with aggregate PER zero, while the 2.23%
pre-FEC BER confirms that FEC still corrected channel errors. The subsequent
AWGN campaign measured a 5–6 dB legacy polyphase gap and replaced the first
Simulink candidate with an exact FFT correlator. Reprocessing this dataset with
an adaptive preamble reference and joint upchirp/downchirp timing-CFO estimate
retained 130/130: all 130 selected the FFT correlator and none required
polyphase fallback. The earlier 56/74 split was primarily a synchronization
defect. The next hardware timing step requires a safely attenuated cable path
and a timestamp closer to RF than the ESP32 millisecond counter.
