# Heltec WiFi LoRa 32 V4 + SX1262 reference transmitter

This project provides the same stopped-by-default serial-controlled transmitter
used by the LR1121 bench, adapted to the Heltec V4 SX1262 and its external RF
front end. The default packet is the deterministic 32-byte `ZLP1` counter frame
at 868.1 MHz, SF7, BW 125 kHz, CR 4/5, and 0 dBm SX1262 output setting.

## Hardware revision warning

Heltec V4 revisions do not use an SX1262 reference RF path:

- V4.2 uses a GC1109 FEM. GPIO7 powers the FEM rail, GPIO2 enables it, SX1262
  DIO2 selects TX/RX, and GPIO46 selects full-PA versus bypass mode.
- V4.3 uses a KCT8103L FEM with different control semantics involving GPIO5.

This firmware powers and enables the FEM but holds GPIO46 and GPIO5 low. That
selects the GC1109 bypass path and deliberately does not enable either external
PA. The accepted SX1262 power range is limited to -17..0 dBm. Do not transmit
until the PCB revision and antenna connection are confirmed.

The mapping follows the Heltec schematic and the Meshtastic Heltec V4 board
definition: SCK/MISO/MOSI/NSS are GPIO 9/11/10/8, DIO1 is 14, RESET is 12,
BUSY is 13, and the TCXO setting is 1.8 V.

## Backup and recovery

The connected test board was backed up before flashing:

```text
G:\Programs\7020\backups\20260802T200300-heltec-wifi-lora32-v4-sx1262\flash-full-16MiB.bin
SHA-256 A23B73E914815044601FE549FB8C2BC8DF8A5F9701EF5A194271C83130E3C28E
```

Restore all 16 MiB only to that same board after verifying the path and MAC
`10:BD:A3:5A:57:90`.

## Build and upload

```powershell
cd firmware/heltec-v4-sx1262-tx
pio run
pio run --target upload --upload-port COM10
```

The firmware never starts periodic RF after boot. Use `show`, `version`, and
`help` for read-only checks. `send` transmits one packet; `start` must be issued
explicitly over USB serial for periodic transmission. The BOOT button is an
emergency stop and cannot start RF.
