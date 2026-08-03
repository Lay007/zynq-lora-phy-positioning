# Hardware test-bench requirements

## Known starting equipment

- 3 × ZynqSDR receivers (exact board revision, RFIC, and clock I/O to verify).
- 1 × Heltec WiFi LoRa 32 V4 with ESP32-S3 + SX1262. The connected unit was
  electrically identified as V4.3 (`GPIO5 high: 0/32`) and validated OTA with
  the external KCT8103L PA disabled; its antenna connection was confirmed.
- 1 × PlutoSDR receiver.
- 1 × RTL-SDR receiver (exact model, tuner, and oscillator to record).
- 30 dB RF attenuator, DC block, and an RF splitter/combiner.
- NanoVNA H4 for cable, antenna, filter, and path comparison measurements.

Do not connect a LoRa transmitter directly to an SDR input. Heltec advertises
`28 +/- 1 dBm` maximum LoRa TX power for V4; 30 dB attenuation alone could
therefore leave approximately -1 dBm before cable losses and is not an approved
cable path. Confirm the actual configured output power and both SDR input
limits, calculate the full power budget, then begin with the highest safe
attenuation and reduce it while watching for clipping.

## Verify before buying clock hardware

For every ZynqSDR board, identify from its schematic and bring-up software:

- RFIC model and board revision;
- external reference input frequency, level, impedance, and connector;
- availability of RFIC synchronization pins;
- a PL-connected input suitable for a common epoch/PPS pulse;
- FPGA/sample-clock relationships and reset behavior;
- deterministic latency across power cycles and reconfiguration.

A shared reference improves frequency coherence but does not, by itself, align
sample counters or guarantee coherent independent RF local oscillators. Initial
TDoA needs a common sample-rate reference, an epoch delivered to PL, and stable
calibrated delay; absolute RF phase coherence is not a first-stage requirement.

## Minimum cable-test setup

```text
SX1262/ZynqSDR TX
       │
  50–60 dB attenuation
       │
  DC block if required
       │
  characterized 1→3 splitter
       ├── matched cable ── RX1
       ├── matched cable ── RX2
       └── matched cable ── RX3

common reference ── buffered distribution ── RX1/RX2/RX3
common epoch/PPS ── logic-level fan-out ───── PL on RX1/RX2/RX3
```

Required additions:

- buffered low-jitter reference distribution (not an unmatched passive tee);
- common epoch/PPS source and logic-level fan-out compatible with each board;
- matched 50 Ω cables or measured per-cable delay;
- 3, 6, 10, and 20 dB attenuators, preferably duplicates;
- 50 Ω terminations, adapters, and documented RF power limits;
- oscilloscope or time-interval measurement access for reference/PPS checks.

GPS discipline is not required for co-located cable tests. It becomes relevant
when stations cannot share a wired reference and epoch.

## OTA and field additions

- matched 868 MHz antennas for the three receivers;
- correct pigtails for Heltec boards and strain relief;
- surveyed antenna coordinates, height, orientation, and polarization;
- tripods or fixed mounts;
- optional 868 MHz band-pass filtering after baseline sensitivity is known;
- low-noise independent power, weather protection, and remote health logging;
- per-station GNSS timing only after wired synchronization is characterized.

Check that every radio and antenna matches the intended regional band, and
follow local spectrum rules for frequency, duty cycle, and transmit power.

## Calibration sequence

1. Characterize cables, splitter loss, and path group-delay differences.
2. Feed the same attenuated signal to all receivers.
3. Verify counter alignment at the common epoch.
4. Measure timestamp offset and drift across power cycles, temperature, gain,
   sample rate, and center frequency.
5. Store corrections with a calibration identifier and uncertainty.
6. Only then replace cables with antennas and attempt positioning.

## Safety checklist

- Calculate worst-case receiver input power before enabling TX.
- Terminate every unused splitter/distribution output correctly.
- Confirm DC-block placement and whether any port carries bias voltage.
- Apply an antenna or 50 Ω load before RF transmission.
- Keep TX and sensitive RX equipment separated during OTA bring-up.
