# Методика BER/SER/PER

[English version](../ber-methodology.md)

В проекте есть два разных AWGN-эксперимента: uncoded baseline CSS-демодулятора
и полная пакетная цепочка с hard decisions. Их нельзя смешивать на одном уровне
интерпретации.

## Uncoded CSS baseline

Эксперимент передаёт независимые равномерные CSS symbol indices, добавляет
комплексный AWGN, выполняет dechirp и `2^SF`-point FFT и выбирает максимальный
bin. SER — доля неверных symbol indices. Uncoded BER сравнивает их естественные
двоичные метки.

В baseline не входят:

- обнаружение преамбулы и ошибки времени;
- CFO/SFO, multipath, clipping и RF-искажения;
- whitening, interleaving, FEC, header и CRC;
- отклонение и повторная передача пакета.

Это характеристика демодулятора, а не LoRa packet error performance.

## Определение SNR

`SNR_dB` — отношение средней мощности комплексного signal sample к средней
мощности комплексного noise sample до dechirp. При `samplesPerChip = L`:

```text
Fs = BW × L
Ns = 2^SF × L
Es/N0 [dB] = SNRsample [dB] + 10 log10(Ns)
Eb/N0 [dB] = SNRsample [dB] + 10 log10(Ns / SF)
```

Последняя формула относится к uncoded label с `SF` bits/symbol. Для пакетного
PHY информационный `Eb/N0` должен учитывать всю энергию преамбулы, header, CRC и
избыточных FEC bits на число user payload bits.

Параметры uncoded-графика:

| Параметр | Значение |
|---|---:|
| SF | 7 |
| samples/chip | 2 |
| symbols/SNR | 4000 |
| bits/SNR | 28000 |
| SNR | −20:2:0 dB |
| seed | 7 |

Исходные значения: [`css-ber-sf7.csv`](../data/css-ber-sf7.csv).

## Нулевые наблюдаемые ошибки

Отсутствие ошибок в конечном прогоне не доказывает BER=0. На logarithmic plot
такая точка рисуется на уровне `0.5/N`, где `N` — число испытаний. В CSV
сохраняются фактический ноль, error count и denominator.

Для низких BER нужен stopping rule: минимальное число наблюдаемых ошибок плюс
максимальное число обработанных bits, а также confidence interval.

## Coded packet experiment

`simulate_coded_ber` создаёт случайный payload, explicit header, CRC, whitening,
FEC, interleaving, Gray mapping и CSS waveform, добавляет AWGN и выполняет
обратную цепочку. Время начала известно, преамбула не передаётся. Поэтому график
характеризует packet coding и hard CSS decisions, но не acquisition.

Параметры committed comparison:

| Параметр | Значение |
|---|---:|
| SF | 7 |
| samples/chip | 2 |
| payload | 16 bytes |
| header / CRC | explicit / enabled |
| coding rates | 4/5 и 4/8 |
| packets на SNR и CR | 100 |
| SNR | −20:2:−6 dB |

Результаты:

- [график](../images/lora-coded-ber-sf7.png);
- [CR 4/5 CSV](../data/lora-coded-ber-sf7-cr1.csv);
- [CR 4/8 CSV](../data/lora-coded-ber-sf7-cr4.csv).

## Метрики

| Метрика | Точка сравнения | Что характеризует |
|---|---|---|
| SER | TX/RX CSS indices | синхронизацию и демодуляцию |
| Pre-FEC BER | coded bits после обратного interleaving | канал и модуляцию |
| Post-FEC BER | исходные bits / FEC output | остаточные ошибки decoder |
| Payload BER | исходный / dewhitened payload | всю bit chain |
| PER/FER | неверный payload или failed CRC | видимую приложению надёжность |
| Undetected errors | CRC pass при неверном payload | безопасность CRC, будущий counter |

Если header не декодирован или длина результата неверна, `PayloadBER` считает
ошибочными все payload bits. `PER` считает ошибкой failed header, failed CRC или
любое расхождение payload. Так failed packets не исчезают из denominator.

Будущий acquisition-inclusive эксперимент должен отдельно считать:

```text
attempted packets
detected preambles
synchronized frames
decoded headers
CRC-pass packets
bit-correct payloads
```

Это не позволяет назвать пропущенную преамбулу bit error или молча исключить
CRC-rejected packet из BER.
