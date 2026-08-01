# BER/SER/PER methodology

The repository contains two distinct AWGN experiments: an uncoded CSS
demodulator baseline and a complete hard-decision packet-coding experiment.

## What the current curve measures

The experiment transmits independent uniformly distributed CSS symbol indices,
adds circular complex AWGN, performs dechirp and a `2^SF`-point FFT, and selects
the largest bin. Symbol error rate (SER) is the fraction of incorrect indices.
Uncoded bit error rate (BER) compares their natural binary labels.

This deliberately excludes:

- preamble detection and symbol-timing failures;
- CFO/SFO, multipath, clipping, and RF impairments;
- whitening, interleaving, FEC, header, and CRC;
- packet rejection and retransmission behavior.

It is therefore a demodulator baseline, not LoRa packet-error performance.

## SNR convention

`SNR_dB` is the ratio of average complex signal-sample power to average complex
noise-sample power before dechirp processing. For `samplesPerChip = L`, the
sample rate is `Fs = BW × L`; the generated chirp still occupies `BW`.

The current committed plot uses:

| Parameter | Value |
|---|---:|
| Spreading factor | 7 |
| Samples per chip | 2 |
| Symbols per SNR point | 4,000 |
| Bits per SNR point | 28,000 |
| SNR sweep | −20:2:0 dB |
| Random seed | 7 |

The source table is [`docs/data/css-ber-sf7.csv`](data/css-ber-sf7.csv).

For the implemented unit-amplitude waveform, one CSS symbol contains

```text
Ns = 2^SF × samplesPerChip
```

complex samples. For the current uncoded symbol labels, a useful conversion is

```text
Es/N0 [dB] = SNRsample [dB] + 10 log10(Ns)
Eb/N0 [dB] = SNRsample [dB] + 10 log10(Ns / SF)
```

The second expression uses `SF` uncoded label bits per symbol. Once FEC,
preamble, headers, and CRC are included, information-bit `Eb/N0` must instead
use the total transmitted energy divided by the number of user payload bits.

## Reading zero-error points

A run with zero observed errors does not prove that BER or SER is zero. For a
logarithmic plot, zero-error points are displayed as filled markers at `0.5/N`,
where `N` is the number of bits or symbols tested. Raw CSV values remain zero.

For publication-quality low-BER results, replace the fixed trial count with a
stopping rule such as a minimum number of observed errors plus a maximum number
of processed bits, and report a confidence interval.

## Implemented coded packet experiment

`simulate_coded_ber` generates random payload bytes, builds the explicit header,
CRC, whitening, FEC, interleaving, Gray mapping, and CSS waveform, then reverses
the chain after AWGN. Timing is known and no preamble is sent, so the curve
isolates packet coding plus hard CSS decisions rather than acquisition.

The committed comparison uses:

| Parameter | Value |
|---|---:|
| Spreading factor | 7 |
| Samples per chip | 2 |
| Payload | 16 bytes |
| Header / CRC | explicit / enabled |
| Coding rates | 4/5 and 4/8 |
| Packets per SNR and CR | 100 |
| SNR sweep | -20:2:-6 dB |

The plot is [`docs/images/lora-coded-ber-sf7.png`](images/lora-coded-ber-sf7.png).
Raw results are stored in
[`lora-coded-ber-sf7-cr1.csv`](data/lora-coded-ber-sf7-cr1.csv) and
[`lora-coded-ber-sf7-cr4.csv`](data/lora-coded-ber-sf7-cr4.csv).

One curve cannot describe the whole receiver. The experiment reports the
implemented metrics below and reserves one counter for later CRC safety work:

| Metric | Comparison point | What it isolates |
|---|---|---|
| SER | transmitted vs detected CSS indices | synchronization/demodulation |
| Pre-FEC BER | interleaver-output bits vs received hard/soft bits | modulation and channel |
| Post-FEC BER | original bits vs FEC-decoder output | residual decoder errors |
| Payload BER | original payload vs dewhitened payload | complete bit pipeline |
| PER/FER | packets with any payload error or failed CRC | application-visible reliability |
| Undetected-error rate | CRC-pass packets with wrong payload | CRC safety check (planned counter) |

For `PayloadBER`, a header failure or an output with the wrong length counts all
payload bits as erroneous. This conservative rule keeps failed packets in the
denominator. `PER` counts a header failure, CRC failure, or any wrong payload as
a packet error. Zero observations are plotted at `0.5/N`, while CSV values and
raw counts remain exact.

For every SNR point, the experiment records raw error counts and denominators
instead of only decimal rates. A future acquisition-inclusive experiment must
add these separate state counters:

```text
attempted packets
detected preambles
synchronized frames
decoded headers
CRC-pass packets
bit-correct payloads
```

This separation prevents a missed preamble from being mislabeled as a decoder
bit error and prevents CRC-rejected packets from silently disappearing from the
reported BER.
