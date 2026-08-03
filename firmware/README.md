# Firmware workspace

Firmware is separated by target and role. Board-specific code must keep RF
configuration separate from experiment configuration, expose firmware/build
revisions, and transport typed metadata rather than relying only on free-form
console logs.

## Available firmware

- [`lilygo-t3s3-lr1121-tx/`](lilygo-t3s3-lr1121-tx/) — PlatformIO reference
  LoRa transmitter for the LILYGO T3S3 V1.2 + LR1121 board. It provides the
  baseline SF7/BW125 profile, deterministic counter payloads, OLED status,
  BOOT-button control, and USB serial commands for profile sweeps.
- [`heltec-v4-sx1262-tx/`](heltec-v4-sx1262-tx/) — stopped-by-default
  serial-controlled transmitter for Heltec WiFi LoRa 32 V4. Firmware 0.2.0
  passively distinguishes V4.2 from V4.3 before RF, selects the corresponding
  external-FEM transmit bypass, and blocks transmission if the result is
  ambiguous. The BOOT button can only stop transmission.

Future Zynq processing-system software and host control remain in this
workspace alongside the external test-equipment firmware.
