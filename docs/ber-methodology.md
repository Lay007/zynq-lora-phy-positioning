# CSS BER/SER methodology

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

## Reading zero-error points

A run with zero observed errors does not prove that BER or SER is zero. For a
logarithmic plot, zero-error points are displayed as filled markers at `0.5/N`,
where `N` is the number of bits or symbols tested. Raw CSV values remain zero.

For publication-quality low-BER results, replace the fixed trial count with a
stopping rule such as a minimum number of observed errors plus a maximum number
of processed bits, and report a confidence interval.
