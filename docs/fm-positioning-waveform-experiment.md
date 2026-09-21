# FM waveform shape for positioning

This model-level experiment asks whether changing the frequency law of a chirp
can improve delay estimation while duration, swept bandwidth, and energy stay
fixed. It compares classic LFM, a deliberately aggressive sinusoidal NLFM, and
a constrained, numerically selected FM law.

This is floating-point evidence only. It does not establish LoRa packet
compatibility, FPGA cost, spectral-mask compliance, RF performance, or
board-level positioning accuracy.

## Reproduce the run

From an environment with the package and development dependencies installed:

```powershell
python tools/run_fm_positioning_experiment.py `
  --output docs/data/fm-positioning `
  --trials 2000 `
  --seed 20260921 `
  --snr-db 0 5 10 15 20
```

The committed report was generated from clean commit `0cc1982` on branch
`experiment/fm-positioning-waveforms`. The full hash and clean/dirty state are
recorded in [`summary.json`](data/fm-positioning/summary.json).

## Equal-resource definition

Every signal uses:

- 1 MS/s complex-baseband sampling;
- 1024 samples, or 1.024 ms;
- the same monotone sweep from -62.5 to +62.5 kHz (125 kHz total);
- energy normalized to one.

For normalized time `x` in `[-1, 1]`, the search family is

```text
f(x) = B/2 * (x + a1*sin(pi*x) + a2*sin(2*pi*x)).
```

LFM is `(a1, a2) = (0, 0)`. The fixed sinusoidal NLFM uses `(0.28, 0)` and
dwells near the band edges, increasing the frequency second moment. The
optimized law was selected from `a1=-0.04:0.02:0.30` and
`a2=-0.06:0.01:0.06`, subject to a positive normalized slope of at least 0.02,
PSL no worse than -10 dB, and ISL no worse than -1.5 dB. Among the 92 feasible
candidates, the objective was

```text
0.85 * (delay CRLB standard deviation / LFM)
+ 0.15 * (absolute Doppler delay displacement / LFM).
```

The selected coefficients are `(0.18, -0.06)`. This is a deterministic
two-parameter grid result, not a global optimum over arbitrary FM signals.

RMS bandwidth is the energy-weighted central second moment of the interior
instantaneous-frequency law. The identical ideal rectangular gate is excluded:
its discontinuity would otherwise give an unbounded continuous-time spectral
second moment and obscure the phase-law comparison.

## Deterministic metrics

The CRLB column uses `Es/N0 = 20 dB`. Mainlobe width is measured between the
first autocorrelation minima. Range values use one-way propagation.

| waveform | RMS bandwidth, kHz | delay CRLB, ns | CRLB range, m | mainlobe, us | PSL, dB | ISL, dB | delay at +86.86 Hz, samples |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| LFM | 36.120 | 311.6 | 93.4 | 16 | -13.48 | -9.76 | -0.697 |
| sinusoidal NLFM | 46.403 | 242.5 | 72.7 | 12 | -6.68 | +0.74 | -0.536 |
| optimized FM | 43.550 | 258.4 | 77.5 | 12 | -10.04 | -1.79 | -0.577 |

Relative to LFM, the fixed NLFM increases RMS bandwidth by 28.5% and lowers
the delay-CRLB standard deviation by 22.2%. The optimized law gains 20.6% RMS
bandwidth and lowers the bound by 17.1%. Both narrow the sampled null-to-null
mainlobe by 25%.

The cost is visible in the sidelobes. The fixed NLFM loses 6.80 dB of PSL and
10.49 dB of ISL; its total sidelobe energy exceeds its mainlobe energy. The
constrained law limits the PSL to -10.04 dB but still loses 3.45 dB of PSL and
7.97 dB of ISL relative to LFM. It is therefore the more credible compromise
for acquisition, not the waveform with the lowest theoretical delay variance.

## AWGN and mobile results

The Monte Carlo uses the existing parabolic matched-filter ToA estimator. Each
waveform gets its matched template, the same Gaussian draws for each condition,
and 2000 trials. SNR means `Es/N0`; the injected delay is grid-aligned. An
outlier is an error greater than one sample.

| case | LFM RMSE, samples | sinusoidal NLFM | optimized FM |
| --- | ---: | ---: | ---: |
| 15 dB, no Doppler | 0.564 | 0.436 | 0.513 |
| 20 dB, no Doppler | 0.316 | 0.235 | 0.248 |
| 20 dB, +86.86 Hz | 0.762 | 0.594 | 0.637 |

At 20 dB without Doppler, the fixed and optimized laws reduce RMSE by 25.6%
and 21.7%, respectively. Near 15--20 dB the results follow the CRLB ordering.
At 10 dB and below threshold errors dominate: lower CRLB alone does not produce
lower total RMSE, so the result must not be extrapolated into the acquisition
threshold region.

The mobile case uses 30 m/s at an 868 MHz carrier, giving 86.86 Hz Doppler. With
no Doppler compensation the deterministic ambiguity-peak displacement maps to
one-way biases of -208.9 m for LFM, -160.7 m for fixed NLFM, and -173.0 m for
optimized FM. Including noise, the two nonlinear laws reduce 20 dB RMSE by
22.0% and 16.4%. The remaining bias is large: waveform shaping helps but does
not replace CFO/Doppler estimation or an up/down-chirp cancellation scheme.

## Evidence files

- [`waveform-metrics.csv`](data/fm-positioning/waveform-metrics.csv): equality
  checks, RMS bandwidth, CRLB, autocorrelation, and the mobile ambiguity point;
- [`ambiguity-cuts.csv`](data/fm-positioning/ambiguity-cuts.csv): ambiguity-peak
  delay and loss over -500 to +500 Hz, including the exact mobile Doppler;
- [`monte-carlo-toa.csv`](data/fm-positioning/monte-carlo-toa.csv): every AWGN
  and mobile condition;
- [`summary.json`](data/fm-positioning/summary.json): configuration,
  provenance, optimization definition, and compact metrics.

The next useful step is a Pareto search over delay variance, sidelobes, and
Doppler coupling followed by a paired up/down-waveform test. Only after that
should a candidate be mapped into fixed point or RTL.
