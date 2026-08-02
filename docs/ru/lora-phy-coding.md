# Этапы кодирования LoRa PHY

[English version](../lora-phy-coding.md)

Здесь описана реализованная MATLAB-модель пакетного кодирования с жёсткими
решениями. Соглашения следуют известной reverse-engineered цепочке
Semtech-совместимого PHY. Все промежуточные векторы доступны для последующего
сравнения с Simulink и HDL.

## Порядок обработки TX и RX

```text
TX
байты payload
  → вычислить payload CRC по исходным байтам
  → применить whitening только к payload
  → разделить байты на nibble: младший первым
  → добавить пяти-nibble explicit header перед payload
  → добавить четыре неотбелённых CRC nibble после payload
  → FEC-кодирование каждого nibble
  → диагональный interleaving блоков
  → inverse-Gray и смещение CSS-bin на +1
  → CSS chirp modulation

RX
жёсткие решения по CSS-символам
  → убрать смещение bin и восстановить Gray labels
  → diagonal deinterleaving
  → hard maximum-likelihood FEC decode
  → разобрать и проверить explicit header
  → объединить и dewhiten payload bytes
  → восстановить и проверить payload CRC
  → принять или отклонить пакет
```

Первый блок особый: содержит `SF-2` codeword, всегда использует CR 4/8 и
формирует восемь reduced-rate символов. При SF7 пять nibble explicit header
точно заполняют этот блок. Последующие блоки используют payload CR; при LDRO в
них также находится `SF-2` codeword.

## Whitening

Whitening выполняет XOR каждого payload byte с детерминированной
псевдослучайной последовательностью. Реализованный 8-битный LFSR использует
полином

```text
x^8 + x^6 + x^5 + x^4 + 1
```

и начинается с `0xFF`. Для каждого нового пакета sequence перезапускается.
Первые байты:

```text
FF FE FC F8 F0 E1 C2 85 0B 17 2F 5E BC 78 F1 E3
```

Операция обратима сама себе:

```text
whiten(whiten(payload)) == payload
```

Whitening не добавляет избыточность и не исправляет ошибки. Он разрушает
длинные и повторяющиеся шаблоны до кодирования. CRC nibble в этой цепочке не
отбеливаются. Сдвиг начального состояния sequence разрушит весь payload, даже
если символы приняты без ошибок.

## Forward error correction

Каждый четырёхбитный nibble превращается в систематический codeword длиной
`4 + CR`:

| CR | Номинальная скорость | Бит в codeword | Назначение |
|---:|---:|---:|---|
| 1 | 4/5 | 5 | минимальное airtime |
| 2 | 4/6 | 6 | дополнительная чётность |
| 3 | 4/7 | 7 | усиленная защита |
| 4 | 4/8 | 8 | максимальная защита hard-кода |

Для CR 2…4 и MSB-first data bits `[d0 d1 d2 d3]` используются:

```text
p0 = d0 xor d1 xor d2
p1 = d1 xor d2 xor d3
p2 = d0 xor d1 xor d3
p3 = d0 xor d2 xor d3
```

CR 1 использует один parity bit:

```text
d0 xor d1 xor d2 xor d3
```

MATLAB-декодер сравнивает принятый hard codeword со всеми 16 допустимыми и
выбирает кандидата с минимальным Hamming distance. Расстояние возвращается для
диагностики. Soft-decision декодирование пока не реализовано.

## Диагональный interleaving

Interleaver переставляет кодированные биты, но не добавляет и не удаляет
информацию. Для строки бита codeword `i` и бита выходного символа `j`:

```text
source = mod(i - j - 1, effectiveSF)
```

`effectiveSF` равен `SF` в обычном блоке и `SF-2` для первого блока или LDRO.
Reduced-rate TX добавляет parity bit и ноль до полной ширины SF. RX удаляет два
служебных label bits перед обратной перестановкой.

Так соседние биты одного codeword распределяются по нескольким CSS-символам.
Ошибка одного символа становится небольшими ошибками нескольких codeword, а не
уничтожает один codeword целиком.

## CRC

Payload CRC использует полином `0x1021` и начальное состояние 0. Для
совместимости требуется специфическое завершение: все payload bytes, кроме двух
последних, проходят побитовую CRC-рекурсию; предпоследний byte XOR-ится со
старшим байтом CRC, последний — с младшим. Четыре CRC nibble передаются начиная
с младшего.

CRC обнаруживает остаточные ошибки после FEC, но не исправляет их и не является
аутентификацией или заменой LoRaWAN MIC. Explicit header отдельно содержит
длину payload, CR, признак наличия payload CRC и собственную пятибитную checksum.

## Порядок битов и mapping

- Payload byte разделяется на младший nibble, затем старший.
- Строка codeword представляется MSB first.
- Interleaved label преобразуется Gray → binary и увеличивается на 1 по модулю
  `2^SF`, образуя индекс циклического сдвига CSS.
- RX вычитает это смещение, применяет binary → Gray и deinterleaving.

Это правила совместимости. Неверный порядок nibble, bit или Gray может давать
правдоподобные chirp, но полностью неработоспособные пакеты.

## Тесты и golden-вектор

`TestPacketCoding` проверяет:

1. Известный префикс whitening и самобратимость.
2. Все 16 codeword CR 4/8.
3. Исправление одиночной ошибки в каждой позиции CR 4/8.
4. Обратимость normal/reduced interleaver и mapping.
5. Фиксированные header и payload CRC vectors.
6. Все промежуточные этапы для фиксированного 16-byte payload.
7. Noiseless round-trip для каждого CR.
8. Сырые счётчики и знаменатели эксперимента BER/PER.

Машиночитаемый вектор:
[`model/matlab/golden/lora-phy-sf7-cr1.json`](../../model/matlab/golden/lora-phy-sf7-cr1.json).

Это внутренний regression vector. Окончательная совместимость требует
сравнения с IQ-записями реального SX1262.

## Источники

- [Semtech SX1262](https://www.semtech.com/products/wireless-rf/lora-connect/sx1262)
- [Semtech LoRaWAN FAQ](https://www.semtech.com/design-support/faq/faq-lorawan)
- [Semtech TN1300.05](https://www.semtech.com/uploads/technology/LoRa/predicting-lorawan-capacity.pdf)
- [Исследование LoRa PHY](https://doi.org/10.1016/j.comcom.2020.02.034)
- [EPFL GNU Radio LoRa SDR](https://github.com/tapparelj/gr-lora_sdr)
