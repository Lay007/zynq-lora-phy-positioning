# MATLAB floating-point модель

[English version](../../model/matlab/README.md)

Это авторитетный алгоритмический уровень проекта. Он содержит CSS waveform и
пакетную LoRa-цепочку с жёсткими решениями: explicit header, payload CRC,
whitening, Hamming, diagonal interleaving, Gray mapping и обратный RX-тракт.

## Запуск тестов

```matlab
cd model/matlab
results = run_tests;
assertSuccess(results);
```

## Построение всех графиков

```matlab
outputs = run_visualizations;
```

Только визуализация демодуляции символов:

```matlab
addpath examples
[result, figureHandle] = plot_symbol_demodulation;
```

Экспорт детерминированного packet golden-вектора:

```matlab
vector = export_golden_vectors;
```

Функции пакета используют столбцы. CFO задаётся в циклах на отсчёт. Для
физической частоты дискретизации `Fs`:

```text
cfoNormalized = cfoHz / Fs
```

## Граница packet-модели

`encode_packet` формирует индексы CSS-символов и сохраняет промежуточные
векторы. `decode_packet` принимает жёсткие решения по символам. Стандартная
LoRa-преамбула/sync word, soft decoding и проверка по IQ-записям SX1262 —
следующая граница совместимости. Текущий coded BER предполагает известное
начало пакета.

## Определения BER

`simulate_uncoded_ber` сравнивает двоичные метки переданных и обнаруженных CSS
символов в AWGN. В него не входят преамбула, FEC и CRC.

`simulate_coded_ber` сообщает pre-FEC BER, payload BER, PER, число ошибок
заголовка и CRC. Если заголовок не декодирован или длина неверна, все payload
bits считаются ошибочными — это консервативное определение.
