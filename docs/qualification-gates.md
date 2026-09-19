# ToA/TDoA qualification gates / Критерии квалификации

Snapshot: `9daeb10` (2026-09-19). Tracks [#28](https://github.com/Lay007/zynq-lora-phy-positioning/issues/28)
and [#29](https://github.com/Lay007/zynq-lora-phy-positioning/issues/29); both remain open.

## Evidence boundary / Граница доказательств

The [committed M5/M6 log](clg400-joint-grid-experiment.md) reports 30 + 60
attempts, 29 + 55 captures and 28 + 53 CRC passes at manual gain 25 dB.
Six capture failures are not measured PHY failures. The 79/79 zero-grid
subset is conditional evidence, not overall PER. Raw `experiments/runs/`
directories are ignored by Git: publish a checksummed manifest and accessible
raw artifacts before calling this independently reproducible hardware evidence.
M6 continuity is currently **simulation evidence**, not a deployed board result.

Журнал фиксирует 90 попыток, 84 захвата и 81 CRC; шесть сбоев захвата нельзя
приписать PHY. Выборка 79/79 условна. Сырые серии пока локальные. M6 подтверждён
симуляцией; аппаратная точность ToA, калибровка и TDoA не квалифицированы.

## Ordered next steps / Порядок следующих шагов

| Gate | Safe offline work | Required bench evidence |
|---|---|---|
| Timestamp contract (#28, #29) | State first confirmed preamble event, accepted profile, sample clock, signed fraction/carry, reset/re-arm and rollover; distinguish DMA anchor from packet ToA | Verify RF reference and first IQ sample to PL epoch mapping; detect DMA gaps/overflow |
| M6 continuity (#28) | Run multi-packet and bridge RTL regressions; retain failed-attempt records; audit abort/timeout recovery | Route, timing report, bitstream SHA-256, cold boot, short continuous series before 1000 planned transmissions |
| ToA qualification (#28) | Independent delay/CFO/SFO sweeps, both CFO signs and symbol boundaries; predeclare bias/p95/p99/outlier/miss limits | Publish every attempt with TX/metadata/capture IDs, flags, IQ hash and build/RF configuration; no success-only denominator |
| Calibration (#28, #29) | Define measurement plane and uncertainty table with unknown values left blank | Fixed-gain cable delay increments, RF ground truth, calibration residual, repeat after reset/configuration changes |
| Synchronization (#29) | Audit CLG400 clock/epoch pins and CDC; use ADR 0005 | Two receivers on one split RF input, common clock **and** epoch, residual offset/drift after cold boot |
| Positioning (#29) | Propagate full ToA covariance through pairwise subtraction and solver Jacobian; study geometry and ambiguity | Three calibrated receivers, surveyed points, timing residuals and position-error distributions with counts |

Each row stays open until its evidence exists. A host send timestamp is not RF
ground truth; Q12 resolution is not timestamp accuracy. For a reference receiver
0, `Cov(t_i-t_0, t_j-t_0)` includes the shared reference error. Even independent
receiver errors yield correlated TDoA observations; do not add RMS components
without recording independence/correlation assumptions.

For a saved capture campaign, run:

```bash
python tools/summarize_capture_campaign.py experiments/runs/RUN --planned-attempts 1000
```

Missing or unclassified records produce a nonzero exit status. Explicit capture
failures remain visible separately from CRC failures in completed captures.

Каждый этап закрывается по артефактам. До стенда можно проверить регрессии,
подготовить sweep и формы результатов; неизвестные задержки и точности остаются
пустыми. Изменение gain/FIR/частоты требует проверки применимости калибровки.

The offline MATLAB estimator ID is `matched-filter-log-magnitude-v1`: guarded
three-point interpolation on log magnitude, bounded to +/-0.5 sample. Record
the code commit and parameters too. PL joint up/down grid correction and the
final packet fractional metadata are separate paths; matching the grid does
not by itself qualify the final ToA. Historical measurement JSON is immutable.
