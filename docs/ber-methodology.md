# CSS BER/SER methodology

> Current status: this document describes the implemented uncoded CSS
> demodulator experiment. It does not claim coded LoRa or packet performance.

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

## Metrics to add with the complete PHY

One curve cannot describe the whole receiver. The complete model will report:

| Metric | Comparison point | What it isolates |
|---|---|---|
| SER | transmitted vs detected CSS indices | synchronization/demodulation |
| Pre-FEC BER | interleaver-output bits vs received hard/soft bits | modulation and channel |
| Post-FEC BER | original bits vs FEC-decoder output | residual decoder errors |
| Payload BER | original payload vs dewhitened payload | complete bit pipeline |
| PER/FER | packets with any payload error or failed CRC | application-visible reliability |
| Undetected-error rate | CRC-pass packets with wrong payload | CRC safety check |

For every SNR point, the experiment must record raw error counts and denominators
instead of only decimal rates. Coded and uncoded curves must use the same channel
realizations where practical. Packet experiments must separately count:

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
