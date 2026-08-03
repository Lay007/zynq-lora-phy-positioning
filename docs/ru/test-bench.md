# Требования к аппаратному стенду

[English version](../test-bench.md)

## Имеющееся и ожидаемое оборудование

- 3 × ZynqSDR, точную ревизию, RFIC и clock I/O нужно проверить.
- 1 × Heltec WiFi LoRa 32 V4, ESP32-S3 + SX1262. Подключённая плата определена
  электрически как V4.3 (`GPIO5 HIGH: 0/32`) и проверена по эфиру с отключённым
  внешним PA KCT8103L; подключение антенны было подтверждено.
- 1 × PlutoSDR.
- 1 × RTL-SDR; записать модель, tuner и тип опорного генератора.
- 30 dB RF attenuator, DC block, splitter/combiner.
- NanoVNA H4 для кабелей, антенн, фильтров и сравнения трактов.

Нельзя подключать LoRa TX напрямую к SDR. Для V4 заявлено `28 ± 1 dBm`; после
30 dB attenuation может остаться около −1 dBm без учёта кабеля. Этот аттенюатор
сам по себе не образует разрешённый кабельный тракт. Нужно проверить реальную
настройку TX, maximum safe input приёмника и полный power budget.

## Что проверить до покупки clock hardware

Для каждой ZynqSDR определить по схеме и ПО:

- RFIC и board revision;
- частоту, уровень, impedance и connector внешней опоры;
- RFIC synchronization pins;
- вход PL для общего epoch/PPS;
- связи FPGA/sample clocks и reset behavior;
- детерминированность latency после power cycle и reconfiguration.

Общая опора стабилизирует частоты, но сама по себе не выравнивает sample counters
и не обеспечивает coherence независимых LO. Для первого TDoA нужны общая
sample-rate reference, epoch в PL и стабильная откалиброванная задержка.

## Минимальный кабельный стенд

```text
SX1262/ZynqSDR TX
       │
  рассчитанное attenuation + DC block при необходимости
       │
  измеренный splitter 1→3
       ├── согласованный кабель ── RX1
       ├── согласованный кабель ── RX2
       └── согласованный кабель ── RX3

common reference ── buffered distribution ── RX1/RX2/RX3
common epoch/PPS ─── logic-level fan-out ──── PL RX1/RX2/RX3
```

Необходимые дополнения:

- buffered low-jitter distribution общей опоры, не пассивный unmatched tee;
- общий epoch/PPS и согласованный по уровням fan-out;
- matched 50 Ω cables или измеренная задержка каждого;
- набор 3, 6, 10 и 20 dB attenuators;
- 50 Ω terminations, adapters и документированные RF limits;
- oscilloscope/time-interval access для проверки reference/PPS.

GPS discipline не нужен для совместного кабельного теста. Он понадобится, когда
станции нельзя соединить общей проводной опорой и эпохой.

## OTA и поле

- одинаковые антенны нужного диапазона;
- правильные pigtail и strain relief;
- измеренные координаты, высота, orientation и polarization;
- штативы или фиксированные крепления;
- optional band-pass filter после измерения baseline sensitivity;
- малошумящее питание, защита от среды и remote monitoring;
- GNSS timing только после проверки wired synchronization.

Каждый передатчик и antenna должны соответствовать региональному диапазону.
Нужно соблюдать местные ограничения frequency, duty cycle и TX power.

## Последовательность калибровки

1. Измерить cable loss, splitter loss и разность group delay.
2. Подать один ослабленный signal на все приёмники.
3. Проверить выравнивание counters общим epoch.
4. Измерить timestamp offset/drift по power cycles, temperature, gain, Fs и LO.
5. Сохранить corrections с calibration ID и uncertainty.
6. Только после этого заменить кабели антеннами.

## RF safety checklist

- Рассчитать worst-case input power до включения TX.
- Согласовать все неиспользуемые выходы splitter/distribution.
- Проверить DC block и наличие bias voltage.
- Подключить antenna или 50 Ω load до RF transmission.
- Разнести TX и чувствительные RX при OTA bring-up.
