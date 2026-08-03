# Heltec V4.3/SX1262 to ZynqSDR hardware sweep, 3 August 2026

[Русская версия](ru/hardware-sweep-2026-08-03-heltec-v43.md)

The validated OTA dataset contains 27 modes, 70 transmitter-acknowledged
packets, and 469,762,048 bytes (448 MiB) of immutable CF32 IQ. It is published
through Git LFS under
`captures/reference/2026-08-03-heltec-v43-zynqsdr-mode-sweep/`.

Firmware 0.2.0 identified the unmarked board electrically before powering its
FEM. The official [V4.3 schematic](https://resource.heltec.cn/download/WiFi_LoRa_32_V4/Schematic/HTIT-WB32LAF_V4.3.pdf)
connects GPIO5 to KCT8103L CTX with a 10 kOhm pull-down, whereas the
[V4.2 schematic](https://resource.heltec.cn/download/WiFi_LoRa_32_V4/Schematic/WiFi_LoRa_32_V4.2.pdf)
leaves GPIO5 unused. The observed 0/32 high samples therefore identify V4.3.
Transmission used the KCT8103L bypass path with its external PA disabled, and
the SX1262 setting remained between -9 and -5 dBm. The antenna was confirmed
before RF, and the final state was `running=no`.

The matrix covers SF5 through SF12, 62.5/125/250/500 kHz bandwidths, CR 4/5
through 4/8, -5/-8/-9 dBm, payload and preamble lengths, CRC off, sync word
`0x34`, and inverted IQ. Two USB-CDC acknowledgement timeouts were reacquired;
only their successful replacements are published. Every selected transmit
returned `state=0`, and every published file passed size and SHA-256 checks.

MATLAB R2025a produced 27 profile-constrained inspection reports. Twenty-six
have packet boundaries clear of both capture edges, CFO between -1.811 and
+2.270 kHz, relative SNR between 41.6 and 59.4 dB, and preamble scores from
0.592 to 0.980. The BW 500 kHz recording is valid raw IQ, but the current
wideband detector merged background activity into its interval (start 0 s,
score 0.054, apparent CFO +40.2 kHz); those estimates are not measurement
results and the capture is retained as a regression case.

This is a strong-signal engineering compatibility dataset, not a calibrated
BER/PER, sensitivity, EVM, or output-power measurement. Full on-air SX1262
packet decoding and a controlled SNR/attenuation sweep remain the next BER/PER
step. The complete procedure and limitations are documented in the
[Russian report](ru/hardware-sweep-2026-08-03-heltec-v43.md).
