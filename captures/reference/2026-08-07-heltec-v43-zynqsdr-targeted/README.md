# Heltec V4.3 to ZynqSDR targeted PHY and ToA dataset

This reference dataset was recorded over a fixed 1–2 m OTA path on 7 August
2026 UTC (8 August in Moscow). It targets the open SF5/SF6 acquisition issue,
repeats BW 500 kHz at a valid receiver sample rate, and supplies a longer run
for initial time-of-arrival repeatability analysis.

The five CF32 files contain 69,000,000 complex samples and occupy exactly
552,000,000 bytes (526.4 MiB). Git LFS stores the IQ files. `manifest.json`
contains the exact TX/RX configuration, every TX confirmation, source run ID,
acquisition commit, byte count, and SHA-256 hash.

## Packet results

| Capture | Fs | TX packets | Acquisition | Matching payload | Soft recovered | PER |
|---|---:|---:|---:|---:|---:|---:|
| baseline-sf7-bw125 | 1 MS/s | 10 | 10 | 10 | 0 | 0% |
| sf5-bw125 | 1 MS/s | 30 | 30 | 30 | 0 | 0% |
| sf6-bw125 | 1 MS/s | 30 | 30 | 30 | 0 | 0% |
| sf7-bw500-fs4m | 4 MS/s | 10 | 10 | 10 | 0 | 0% |
| toa-sf7-bw125 | 1 MS/s | 50 | 50 | 50 | 0 | 0% |

Across all 130 transmissions, all 130 pass acquisition, header validation,
CRC, and exact payload comparison. The aggregate PER is zero. The pre-FEC BER
is still 2.23%, so this result demonstrates successful correction rather than
an error-free channel. The adaptive local-floor detector separates
packets that the original global threshold merged during receiver floor
changes. A tighter retry from the activity boundary recovers the remaining
SF5 acquisition ambiguity. Polyphase FFT-power combining uses all eight
oversampling phases instead of discarding seven of them; this removes the
remaining low-SF header/CRC failures. This fixed high-SNR run is not a
sensitivity test.

The BW 500 kHz result replaces the earlier under-sampled Fs=1 MS/s attempt:
with Fs=4 MS/s and the signal 500 kHz away from receiver DC, all ten packets
are acquired and decode without payload bit errors.

## ToA repeatability

The 50-packet SF7 capture produces 50 matched timing observations. After an
affine fit removes the unrelated TX/RX epochs and their 4.95 ppm linear clock
scale error, the residual standard deviation is 18.72 samples (18.72 us) and
the 95th absolute residual is 33.47 samples.

This is complete-chain fixed-geometry OTA repeatability. It includes TX
millisecond timestamp quantization, scheduling, RF/baseband latency variation,
multipath, and RX estimation error. It is not an absolute propagation-delay or
calibrated TDoA result.

## Reproduce the reports

```matlab
cd model/matlab
addpath examples
d = "../../captures/reference/2026-08-07-heltec-v43-zynqsdr-targeted";
packetReport = evaluate_reference_sweep(d, OutputDirectory=d);
toaReport = evaluate_reference_toa(d, "toa-sf7-bw125", ...
    OutputDirectory=d);
```

Generated files:

- `packet-performance.csv` — one row per transmission;
- `case-performance.csv` and `performance-summary.json` — mode aggregates;
- `toa-repeatability.csv` — one row per matched timing observation;
- `toa-summary.json` — fitted clock scale and residual timing metrics.

## Кратко по-русски

Набор подтверждает, что прежний провал BW500 был связан с записью при
недостаточной Fs: при 4 Мвыб/с декодированы все 10 передач. Адаптивная оценка
локального фона и повторная синхронизация от границы активности подняли
acquisition SF5/SF6 до 30 из 30 в каждом режиме. Polyphase-объединение мощностей
FFT использует все восемь фаз передискретизации вместо одной: payload совпал
во всех 130 передачах, итоговый PER равен нулю. При этом pre-FEC BER равен
2,23%, поэтому канал не был безошибочным — ошибки исправил FEC. Повторяемость
всей OTA-цепочки ToA после удаления линейного drift равна 18,72 мкс по
стандартному отклонению; это ещё не аппаратно откалиброванный ToA.
