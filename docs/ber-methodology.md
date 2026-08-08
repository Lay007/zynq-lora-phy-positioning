# BER/SER/PER methodology

[Русская версия](ru/ber-methodology.md)

The repository keeps demodulator errors and packet-decoder errors as two
separate AWGN experiments. Both use fixed random seeds, raw error counts,
explicit denominators, and two-sided 95% Wilson score intervals.

## Uncoded single-phase versus polyphase comparison

`simulate_uncoded_ber` transmits independent uniformly distributed CSS symbol
indices with known timing. It adds circular complex AWGN, performs dechirp and
a `2^SF`-point FFT, and compares the detected symbol index and its natural
binary label with the transmitted values.

The campaign runs the legacy first-decimation-phase detector and the production
polyphase FFT-power combiner on the same seeded waveform and noise realization:

| Parameter | Value |
|---|---:|
| Spreading factor | 7 |
| Samples per chip, `L` | 1, 2, 4, 8 |
| Demodulators | single-phase, polyphase |
| Symbols per SNR/mode | 4,000 |
| Label bits per SNR/mode | 28,000 |
| SNR sweep | −20:2:−4 dB |
| Seed | `70 + L` |

![Single-phase and polyphase BER/SER](images/css-ber-polyphase-comparison.png)

Raw results: [`css-ber-polyphase-comparison.csv`](data/css-ber-polyphase-comparison.csv).
At `L=8` and −10 dB, observed BER falls from `1.57e−2` to `3.57e−4`, about
44 times lower. At `L=4` the gain is smaller. `L=2` is not monotonically
better: the current noncoherent power sum can combine adjacent-bin energy from
the cyclic chirp wrap and degrade part of the waterfall. This measured caveat
must be resolved or explicitly accepted before the Simulink architecture is
frozen.

The uncoded experiment excludes preamble acquisition, whitening, interleaving,
FEC, header, CRC, packet rejection, CFO/SFO, multipath, and clipping. It is a
demodulator baseline, not application-visible packet performance.

## SNR and energy convention

`SNR_dB` is average complex signal-sample power divided by average complex
noise-sample power before dechirp. For `L = samplesPerChip`:

```text
Fs = BW × L
Ns = 2^SF × L
Es/N0 [dB] = SNRsample [dB] + 10 log10(Ns)
Eb/N0 [dB] = SNRsample [dB] + 10 log10(Ns / SF)
```

The last expression applies to the `SF` uncoded label bits. The uncoded CSV
stores both converted axes. For the coded experiment, `EbN0_dB` uses the total
header/payload-symbol energy divided by user payload bits; no preamble is
included because the experiment starts at a known packet boundary.

## Coded SF5/SF6/SF7 campaign

`simulate_coded_ber` builds the explicit header, payload CRC, whitening,
Hamming FEC, diagonal interleaving, Gray mapping, and CSS waveform, then
reverses the chain after AWGN. It evaluates hard and soft decoders from the
same per-bin FFT metrics.

| Parameter | Value |
|---|---:|
| Spreading factors | 5, 6, 7 |
| Samples per chip | 8 |
| Coding rate | 4/5 |
| Payload | 16 bytes |
| Header / CRC | explicit / enabled |
| Packets per SNR/SF | 200 |
| Payload bits per SNR/SF | 25,600 |
| SNR sweep | −20:2:−4 dB |
| Seeds | 105, 106, 107 |

![Coded low-SF BER and PER](images/lora-coded-ber-sf5-sf7-polyphase.png)

Raw results: [`lora-coded-ber-sf5-sf7-polyphase.csv`](data/lora-coded-ber-sf5-sf7-polyphase.csv).
At −10 dB, the measured hard/soft PER is 100%/74.5% for SF5, 41%/4% for
SF6, and 4%/0% for SF7. The corresponding soft-recovered packet counts are
51, 74, and 8 out of 200. These are finite Monte Carlo observations, not
analytic receiver limits.

## Metric definitions

| Metric | Comparison | Interpretation |
|---|---|---|
| SER | transmitted/detected CSS indices | demodulator symbol errors |
| Pre-FEC BER | transmitted/received interleaver codeword bits | channel plus hard CSS decisions |
| Hard/soft payload BER | original/dewhitened payload | decoder-specific residual errors |
| Hard/soft PER | exact payload plus header/CRC status | decoder-specific packet failure |
| Soft recovered | hard packet failed, soft packet exact | incremental soft-decoder recovery |
| Undetected errors | CRC passed but payload differed | CRC safety observation |

If a decoder returns the wrong payload length, every user payload bit counts as
an error. A packet error is a failed header, failed CRC, wrong length, or any
payload mismatch. No failed packet disappears from a denominator.

## Confidence intervals and zero observations

CSV rates remain exact observed ratios. Each uncoded BER/SER and primary coded
BER/PER metric includes a two-sided 95% Wilson interval. A zero-error run does
not prove a zero underlying rate: plots place it at `0.5/N` only to keep the
marker visible on a logarithmic axis. For example, zero packet errors in 200
trials still has a 95% Wilson upper bound of about 1.88%.

## Reproduce

```matlab
cd model/matlab
addpath examples
campaign = plot_ber_campaign;
```

The command regenerates both PNGs, both CSVs, and
[`ber-polyphase-campaign.mat`](data/ber-polyphase-campaign.mat). The older
SF7-only CSV/PNG files remain as historical baselines; the polyphase campaign
is the current comparison.

The coded experiment still assumes known timing and sends no preamble. A later
acquisition-inclusive hardware sweep must separately count attempted packets,
detected preambles, synchronized frames, decoded headers, CRC-pass packets,
and bit-correct payloads.
