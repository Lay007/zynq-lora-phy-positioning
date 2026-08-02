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

Future Zynq processing-system software and host control remain in this
workspace alongside the external test-equipment firmware.
