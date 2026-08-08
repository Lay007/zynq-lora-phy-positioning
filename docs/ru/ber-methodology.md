# Методика BER/SER/PER

[English version](../ber-methodology.md)

В репозитории отдельно измеряются ошибки демодулятора и ошибки пакетного
декодера. Оба AWGN-эксперимента используют фиксированные seed, исходные
счётчики ошибок, явные знаменатели и двусторонние 95%-интервалы Wilson.

## Сравнение демодуляторов с когерентным эталоном без FEC

`simulate_uncoded_ber` передаёт независимые равномерные CSS symbol indices при
известном времени символа. После добавления комплексного AWGN принятый индекс
и его естественная двоичная метка сравниваются с переданными значениями.

Три приёмника получают одинаковые seeded waveform и noise: legacy FFT по
первой фазе децимации, рабочая некогерентная сумма мощностей polyphase FFT и
точный matched-filter reference. Эталон выполняет циклическую корреляцию всех
комплексных отсчётов со всеми циклическими сдвигами CSS chirp, поэтому
когерентно объединяет `L` отсчётов до сравнения модулей гипотез.

| Параметр | Значение |
|---|---:|
| SF | 7 |
| Samples/chip, `L` | 1, 2, 4, 8 |
| Демодуляторы | single-phase, polyphase, matched-filter |
| Символов на SNR/mode | 4 000 |
| Label bits на SNR/mode | 28 000 |
| SNR sweep | −20:2:−4 dB |
| Seed | `70 + L` |

![Текущий демодулятор и matched-filter reference](../images/css-ber-current-vs-ideal.png)

Исходные результаты: [`css-ber-demodulator-comparison.csv`](../data/css-ber-demodulator-comparison.csv).
При `L=8` интерполяция в логарифмическом масштабе BER даёт проигрыш текущего
приёмника эталону `5,33 dB` при BER `1e−2` и `6,03 dB` при BER `1e−3`. При
`L=1` оба приёмника математически эквивалентны, поэтому измеренный разрыв равен
нулю. Результаты для всех исследованных `L` сведены отдельно:

![Измеренный проигрыш matched filter](../images/css-ber-ideal-gap.png)

Пороги и разрывы: [`css-ber-ideal-gap.csv`](../data/css-ber-ideal-gap.csv).
Проигрыш polyphase не обязан точно равняться `10 log10(L)`: мощности фаз
складываются некогерентно, а энергия соседних bins около циклического переноса
chirp меняет waterfall, особенно при `L=2`. Это ограничение нужно устранить или
явно принять до фиксации Simulink-архитектуры.

Matched filter является идеальным только внутри данного эксперимента: время
символа и форма сигнала известны точно, канал содержит только AWGN, отсутствуют
CFO, SFO, multipath, clipping и quantization. Это не предел Шеннона и не
характеристика обнаружения полного пакета.

В uncoded baseline не входят acquisition, whitening, interleaving, FEC,
header, CRC, packet rejection, CFO/SFO, multipath и clipping. Это характеристика
демодулятора, а не прикладная пакетная надёжность.

## Определение SNR и энергии

`SNR_dB` — отношение средней мощности complex signal sample к средней мощности
complex noise sample до dechirp. Для `L = samplesPerChip`:

```text
Fs = BW × L
Ns = 2^SF × L
Es/N0 [dB] = SNRsample [dB] + 10 log10(Ns)
Eb/N0 [dB] = SNRsample [dB] + 10 log10(Ns / SF)
```

Последняя формула относится к `SF` uncoded label bits. В uncoded CSV сохранены
обе пересчитанные оси. Для coded sweep `EbN0_dB` использует энергию всех
header/payload symbols на число user payload bits; преамбула не учитывается,
поскольку начало пакета известно.

## Coded sweep SF5/SF6/SF7

`simulate_coded_ber` строит explicit header, payload CRC, whitening, Hamming
FEC, diagonal interleaving, Gray mapping и CSS waveform, добавляет AWGN и
выполняет обратную цепочку. Hard и soft decoder получают одни FFT metrics.

| Параметр | Значение |
|---|---:|
| SF | 5, 6, 7 |
| Samples/chip | 8 |
| Coding rate | 4/5 |
| Payload | 16 bytes |
| Header / CRC | explicit / enabled |
| Пакетов на SNR/SF | 200 |
| Payload bits на SNR/SF | 25 600 |
| SNR sweep | −20:2:−4 dB |
| Seeds | 105, 106, 107 |

![Coded BER и PER для SF5/SF6/SF7](../images/lora-coded-ber-sf5-sf7-polyphase.png)

Исходные результаты: [`lora-coded-ber-sf5-sf7-polyphase.csv`](../data/lora-coded-ber-sf5-sf7-polyphase.csv).
При −10 dB hard/soft PER равны 100%/74,5% для SF5, 41%/4% для SF6 и
4%/0% для SF7. Soft decoder дополнительно восстановил 51, 74 и 8 пакетов из
200 соответственно. Это конечный Monte Carlo, а не аналитический предел.

## Метрики

| Метрика | Сравнение | Смысл |
|---|---|---|
| SER | TX/RX CSS indices | ошибки символов демодулятора |
| Pre-FEC BER | TX/RX interleaver codeword bits | канал и hard CSS decisions |
| Hard/soft payload BER | исходный/dewhitened payload | остаточные ошибки декодера |
| Hard/soft PER | payload вместе с header/CRC | пакетная ошибка декодера |
| Soft recovered | hard packet failed, soft packet exact | выигрыш soft decoder |
| Undetected errors | CRC pass при неверном payload | наблюдение безопасности CRC |

Если декодер вернул неправильную длину, ошибочными считаются все user payload
bits. Packet error включает failed header, failed CRC, неверную длину или любое
расхождение payload. Ошибочные пакеты не исчезают из denominator.

## Доверительные интервалы и нулевые ошибки

В CSV остаются точные наблюдаемые отношения. Для uncoded BER/SER и основных
coded BER/PER сохранены двусторонние 95%-интервалы Wilson. Ноль ошибок не
доказывает нулевую вероятность: на logarithmic plot такая точка показана на
уровне `0.5/N`. Например, для 0 ошибок из 200 верхняя граница Wilson всё ещё
равна примерно 1,88%.

## Воспроизведение

```matlab
cd model/matlab
addpath examples
campaign = plot_ber_campaign;
```

Команда заново создаёт три PNG, три CSV и
[`ber-polyphase-campaign.mat`](../data/ber-polyphase-campaign.mat). Старые
SF7-only и двухрежимные CSV/PNG сохранены как исторический baseline; текущим
результатом считается кампания с тремя демодуляторами. Имя MAT-файла сохранено
для совместимости, но его схема теперь `zynq-lora-ber-campaign-v2` и содержит
таблицу `idealGap`.

Coded sweep по-прежнему предполагает известное время и не передаёт преамбулу.
Будущий acquisition-inclusive hardware sweep должен отдельно считать attempts,
detected preambles, synchronized frames, decoded headers, CRC-pass packets и
bit-correct payloads.
