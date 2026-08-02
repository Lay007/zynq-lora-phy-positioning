# SX1262 packet capture with RTL-SDR and PlutoSDR

The first capture goal is not sensitivity or ToA. It is a repeatable
compatibility record in which the transmitted bytes and every LoRa PHY setting
are known. Use PlutoSDR as the primary engineering capture and RTL-SDR as a
quick independent monitor.

## Recommended sequence

1. Inspect the Heltec board label, regional RF variant, antenna, and installed
   firmware before transmitting.
2. Generate deterministic point-to-point LoRa packets, not LoRaWAN packets.
3. Make a short over-the-air capture at the lowest practical TX-power setting.
4. Confirm frequency, packet timing, gain, and absence of clipping.
5. Repeat with both RTL-SDR and PlutoSDR using the same Heltec firmware.
6. Preserve raw IQ and metadata without editing them.
7. Only after OTA works, make a conducted cable capture with calculated
   attenuation and known receiver input limits.

The Heltec WiFi LoRa 32 V4 uses ESP32-S3 and SX1262. Heltec advertises
`28 +/- 1 dBm` LoRa TX power for V4, so never infer conducted power from an
older board or connect its RF output directly to an SDR. At that worst case,
30 dB attenuation alone could still leave approximately -1 dBm at the receiver
before cable losses.

## Deterministic Heltec packet

Start from the current official Heltec point-to-point LoRa transmit example.
Do not begin with LoRaWAN: join state, encryption, counters, and network-layer
fields make the first PHY comparison unnecessarily ambiguous.

Use these initial PHY settings and record their exact firmware constants:

| Setting | Initial value |
|---|---:|
| Carrier | legal frequency for the board variant and region |
| Bandwidth | 125 kHz |
| Spreading factor | 7 |
| Coding rate | 4/5 (`CR=1`) |
| Preamble | 8 symbols |
| Header | explicit |
| Payload CRC | enabled |
| IQ inversion | disabled |
| Sync word | record exact numeric value |
| Payload | 16 fixed-layout binary bytes |
| TX power | lowest practical stable setting |

Recommended 16-byte payload:

```text
offset  size  value
0       2     5A 4C                 magic "ZL"
2       1     01                    payload schema version
3       1     00                    flags
4       4     sequence number       uint32, little endian
8       4     ESP timer value       low uint32, little endian
12      4     A5 5A 3C C3           fixed pattern
```

Log one serial line per transmission containing UTC host time, sequence number,
the complete payload hex string, ESP timer value, TX result, frequency, BW, SF,
CR, header mode, CRC, preamble, sync word, IQ inversion, and TX-power setting.
The sequence number associates an IQ burst with a unique packet even when a
capture starts in the middle of a run.

For the first visual check, transmit periodically with enough separation to see
individual bursts. Choose the interval according to local spectrum rules and
the resulting time on air. A temporary one-second interval is convenient only
where it is permitted; otherwise use a longer interval or a properly attenuated
and shielded conducted setup.

## Receiver tuning plan

Direct-conversion receivers often have a DC component at the exact center of
the recorded spectrum. Therefore do not initially place the LoRa carrier at
zero Hz.

For an example legal carrier `Fsignal = 868.100 MHz`:

```text
SDR center frequency = 868.350 MHz
captured LoRa offset = -250 kHz
digital shift to zero = +250 kHz
```

Use a 1 MS/s Pluto sample rate or 1.024 MS/s RTL-SDR sample rate. Both leave
margin around a 125 kHz LoRa channel and make frequency-offset inspection easy.
The processing step recenters samples with:

```matlab
n = (0:numel(iq)-1).';
iqBaseband = iq .* exp(1j*2*pi*250e3*n/sampleRateHz);
```

The sign must be derived from `Fcenter - Fsignal`; do not guess it from the
waterfall display.

## RTL-SDR capture

RTL-SDR is receive-only and is the quickest way to confirm that the Heltec emits
the expected bursts. Its command-line recorder produces headerless unsigned
8-bit interleaved `I,Q` bytes, so all settings must be stored separately.

1. Attach the correct receive antenna and place it several metres from the
   Heltec for the first OTA test.
2. Check that the device and tuner work:

   ```powershell
   rtl_test -t
   ```

3. Record 30 seconds at a manual starting gain. Replace the example frequencies
   when using another regional variant:

   ```powershell
   rtl_sdr -d 0 -f 868350000 -s 1024000 -g 20 -p 0 -n 30720000 captures/heltec-sf7-cr1-rtl.cu8
   ```

4. Calculate the raw-file checksum immediately:

   ```powershell
   Get-FileHash -Algorithm SHA256 captures/heltec-sf7-cr1-rtl.cu8
   ```

5. Copy [`experiments/templates/phy-capture.yaml`](../experiments/templates/phy-capture.yaml)
   into `experiments/runs/` and record the command, tuner model, serial number,
   gain, PPM correction, expected file size, actual file size, and checksum.

At 1.024 MS/s, 30 seconds contains 30,720,000 complex samples and occupies
61,440,000 bytes. A different size means the capture stopped early or the
requested sample count was interpreted differently by the installed tool;
record the actual count rather than silently repairing the file.

Load the RTL-SDR file in MATLAB:

```matlab
file = fopen("captures/heltec-sf7-cr1-rtl.cu8", "r");
raw = fread(file, Inf, "uint8=>double");
fclose(file);
iq = complex(raw(1:2:end)-127.5, raw(2:2:end)-127.5) / 127.5;
```

Make three short gain captures, for example around 10, 20, and 30 dB, rather
than using AGC for the final reference. Select the lowest manual gain that
keeps packets clearly above the noise without histogram pile-up at the minimum
or maximum sample codes. Leave `-p 0` initially, estimate CFO from LoRa
preambles, then document any PPM correction used in later runs.

## PlutoSDR capture

PlutoSDR is the primary capture source because its AD936x receive path exposes
sample rate, RF bandwidth, LO, and manual gain through libiio. Install the
official IIO driver/runtime, then the Python bindings:

```powershell
python -m pip install pyadi-iio pylibiio
```

Confirm connectivity with `iio_info -s`. Then use the repository recorder:

```powershell
python tools/capture_pluto.py `
  --uri ip:192.168.2.1 `
  --signal-frequency 868100000 `
  --center-frequency 868350000 `
  --sample-rate 1000000 `
  --rf-bandwidth 1000000 `
  --gain 20 `
  --samples 4194304 `
  --timeout-ms 30000 `
  --count 5 `
  --output captures/heltec-sf7-cr1-pluto
```

Each file contains about 4.19 seconds of contiguous complex samples in
little-endian float32 `I,Q` order. Gaps may exist between files. The script
discards warm-up buffers, uses manual gain, writes the actual read-back settings,
and computes SHA-256 for every `.cf32` file.

The IIO timeout must exceed the time needed to acquire and transfer one buffer.
At 1 MS/s, a 4,194,304-sample buffer alone takes more than four seconds to
acquire, so the recorder defaults to a 30-second timeout.

Load one Pluto file in MATLAB:

```matlab
file = fopen("captures/heltec-sf7-cr1-pluto/pluto-...-000.cf32", "r", "ieee-le");
raw = fread(file, Inf, "single=>single");
fclose(file);
iq = complex(raw(1:2:end), raw(2:2:end));
```

Do not concatenate the five files and pretend they are continuous. Process
each buffer independently unless an external trigger or continuous streaming
method proves sample continuity across boundaries.

## Capture-quality checks

Accept a raw capture only when all of these are recorded:

- the LoRa burst is at the expected signed frequency offset;
- at least 20 known sequence numbers are visible or recoverable;
- no I/Q sample-code histogram piles up at either numerical limit;
- manual gain and all frequency/sample-rate settings are known;
- the preamble gives a stable CFO estimate across packets;
- several noise-only intervals exist before and after packets;
- raw file size and SHA-256 match the metadata;
- the Heltec serial log covers the same capture interval;
- antennas, distance, orientation, or the complete cable/attenuator path are
  documented.

Preserve a weak, medium, and strong capture rather than only the prettiest one.
They will expose AGC, clipping, quantization, and threshold problems when the
MATLAB receiver is extended.

## OTA versus conducted capture

Use OTA first because it removes the immediate risk of excessive conducted
power. Use low TX power, correct antennas on both devices, physical separation,
and short test runs.

For a cable test, do not use the currently available 30 dB attenuator by itself.
First verify the exact Heltec V4 output setting and both SDR maximum safe input
levels, calculate worst-case received power, and add sufficient fixed
attenuation plus a DC block where required. Begin at the highest calculated
attenuation, check for clipping, and reduce attenuation in small documented
steps. Never hot-switch an unterminated transmitter output.

## Capture matrix after the first successful packet

Keep payload and sync word fixed, and change one variable per run:

| Run | Receiver | SF | CR | Purpose |
|---|---|---:|---:|---|
| 1 | RTL-SDR | 7 | 4/5 | quick independent RF confirmation |
| 2 | PlutoSDR | 7 | 4/5 | primary MATLAB compatibility vector |
| 3 | PlutoSDR | 7 | 4/8 | verify FEC/interleaver mode change |
| 4 | PlutoSDR | 8 | 4/5 | verify symbol-duration scaling |
| 5 | PlutoSDR | 7 | 4/5 | weak-signal capture |
| 6 | PlutoSDR | 7 | 4/5 | strong but unclipped capture |

Do not sweep SF, CR, frequency, gain, and payload simultaneously. A one-variable
matrix makes a mismatch traceable to one stage of the MATLAB chain.

## References

- [Heltec WiFi LoRa 32 V4 documentation](https://docs.heltec.org/en/node/esp32/wifi_lora_32/index.html)
- [Official Heltec ESP32 library and examples](https://github.com/HelTecAutomation/Heltec_ESP32)
- [Analog Devices PlutoSDR quick start](https://wiki.analog.com/university/tools/pluto/users/quick_start)
- [Analog Devices pyadi-iio Pluto interface](https://analogdevicesinc.github.io/pyadi-iio/devices/adi.ad936x.html)
- [Analog Devices libiio receive workflow](https://wiki.analog.com/university/tools/pluto/controlling_the_transceiver_and_transferring_data)
- [`rtl_sdr` command reference](https://manpages.debian.org/testing/rtl-sdr/rtl_sdr.1.en.html)
