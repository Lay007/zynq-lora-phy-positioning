# LoRa PHY Inspector

LoRa PHY Inspector is the project-native MATLAB tool for looking inside an IQ
recording before attempting packet decoding. It loads a headerless recording,
finds the strongest CSS burst, estimates its main parameters, and shows the
same intermediate representations that will later become Simulink and RTL
receiver blocks.

![LoRa PHY Inspector](images/lora-phy-inspector.png)

## Start the application

From the repository root:

```matlab
cd model/matlab
addpath apps
app = lora_phy_inspector;
```

To try it without radio hardware, generate the deterministic example first:

```matlab
addpath examples
file = generate_inspector_demo_capture;
app = lora_phy_inspector;
app.FileField.Value = file;
app.SampleRateField.Value = 500e3;
```

Then press **Analyze**. The example contains an SF7, BW 125 kHz research frame
at a +40 kHz offset from the capture centre.

## Input fields

- **IQ file** — a headerless interleaved complex recording.
- **Format** — `auto`, `cu8`, `cf32`, or `ci16`. Automatic selection uses the
  filename extension; `.pcm`, `.ci16`, and `.sc16` are treated as signed
  complex int16.
- **Fs** — actual IQ sample rate in samples per second.
- **Centre** — SDR tuning frequency in hertz. It is used only to present the
  estimated absolute carrier frequency.
- **Expected frequency** — nominal transmitter frequency. Set it to zero when
  it is unknown; otherwise the application reports CFO relative to it.

Supported file layouts are:

| Format | Extensions | Component order | Scaling |
|---|---|---|---|
| RTL-SDR CU8 | `.cu8`, `.uc8` | unsigned 8-bit `I,Q,I,Q,...` | mapped approximately to `[-1,1]` |
| Pluto/GNU Radio CF32 | `.cf32`, `.fc32`, `.cfile` | little-endian float32 `I,Q,I,Q,...` | preserved as stored |
| CI16/SC16 | `.pcm`, `.ci16`, `.sc16` | little-endian signed int16 `I,Q,I,Q,...` | divided by 32768 |

### HDL PCM

The HDL testbench now writes a **conventional CI16** stream without a custom
32-bit packed-file interpretation:

```text
I0, Q0, I1, Q1, ...
```

Each component is signed little-endian `int16`. Inside the HDL,
`data_out[31:16]` is `I` and `data_out[15:0]` is `Q`; the testbench explicitly
emits bytes as `I_lo,I_hi,Q_lo,Q_hi`. A standard complex-int16 reader therefore
sees the correct I/Q order directly.

`phase_to_sample` currently produces roughly Q14 amplitude (`±16384`). That is
a numerical property of the HDL signal, not a separate file format. Inspector
normalizes CI16 by the full signed-int16 range, 32768, so a nominal HDL chirp
appears with magnitude around `0.5`.

HDL recording names must encode the key parameters:

```text
hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
```

For example:

```text
hdl_sf7_bw125k_fs2000k_package.pcm
```

Use the helper beside the recordings:

```matlab
cd hdl/signal
open_in_inspector("hdl_sf7_bw125k_fs2000k_package.pcm")
```

It parses SF/BW/Fs from the filename, selects `ci16`, and fills in the sample
rate in Inspector. See `hdl/README.md` for the precise file and naming contract.

Raw files carry no metadata. For other captures, keep sample rate, centre
frequency, gain, radio configuration, and experiment identity beside every
recording as described in the [capture guide](iq-capture-guide.md).

## What the four plots mean

1. **Overview spectrogram** locates the strongest energetic burst and shows
   the selected start and end. It is the first check for clipping, aliases,
   interferers, and an incorrect centre frequency.
2. **Selected packet** overlays magnitude and phase-difference instantaneous
   frequency. A LoRa upchirp appears as a rising ramp with a periodic wrap; a
   downchirp slopes down.
3. **Average spectrum** shows occupied bandwidth, estimated carrier, and the
   snapped LoRa bandwidth boundaries.
4. **Dechirped FFT** has time-ordered symbols in rows and FFT bins in columns.
   Repeated preamble upchirps form repeated bright peaks. Downchirps do not
   collapse to one bin with an upchirp reference and therefore appear spread.

When the working signal is oversampled, each row combines FFT power from every
polyphase chip-rate view. No single decimation phase is treated as privileged.

The symbol list contains hard FFT-bin decisions. It is diagnostic output, not
proof that a standards-compliant packet was decoded.

## Estimates and method

The current estimator:

1. computes short-block energy and selects the strongest contiguous burst;
2. estimates occupied bandwidth and carrier from the instantaneous-frequency
   distribution, then snaps bandwidth to 125, 250, or 500 kHz;
3. compares normalized autocorrelation at candidate LoRa symbol periods to
   estimate SF5 through SF12;
4. refines the first upchirp boundary with dechirp and FFT concentration;
5. estimates residual frequency error from repeated preamble upchirps;
6. reports relative signal/noise power, SNR, DC offset, I/Q power imbalance,
   and integer-component clipping for CU8/CI16.

All DSP is implemented without Communications Toolbox or Signal Processing
Toolbox dependencies. The analyzer API can also be used without the UI:

```matlab
[iq, info] = lora_phy.load_iq_capture("capture.cf32", "auto");
result = lora_phy.inspect_iq_capture(iq, 1e6);
```

## Measurement limits

- Only the strongest burst is analyzed; multi-packet browsing is not yet
  implemented.
- The GUI remains an estimator for an unknown capture. For a known BW/SF
  profile, `receive_lora_packet` now performs standard sync/header/payload
  decoding and CRC validation on real SX1262 recordings.
- Signal power is relative to the stored sample scale. It is not calibrated
  RSSI or received power in dBm.
- Bandwidth and SF estimation assume a LoRa-like CSS preamble and the standard
  candidate sets.
- The current project frame is `8 upchirps + 2 downchirps + uncoded symbols`.
  Standard LoRa sync-word/header waveform detection and SX1262 payload decoding
  remain a separate interoperability milestone.
- Live streaming from PlutoSDR and RTL-SDR is not yet part of the application;
  capture to a file first.

For independent visual checks, the same recordings can be opened in
[Inspectrum](https://github.com/miek/inspectrum). SDRangel can be used for live
radio inspection, and [gr-lora_sdr](https://github.com/tapparelj/gr-lora_sdr)
is a useful independent LoRa receiver reference. These tools complement rather
than replace the traceable MATLAB-to-Simulink implementation in this project.
