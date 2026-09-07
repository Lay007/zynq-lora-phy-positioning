# LoRa PHY: структура сигнала и формат кадра

Этот документ описывает **физический уровень LoRa (LoRa PHY)**: CSS-модуляцию,
структуру преамбулы, sync word, SFD, explicit/implicit header, полезную нагрузку,
FEC, CRC и расчёт Time-on-Air.

Важно различать два уровня:

- **LoRa** — физический радиоинтерфейс на основе Chirp Spread Spectrum (CSS);
- **LoRaWAN** — MAC/сетевой протокол, который использует LoRa как один из PHY.

Поэтому `LoRa PHY header`, `payload CRC` и `LoRaWAN MHDR/MIC` — разные сущности.

Для подробностей внутреннего кодирования payload см. также
[Whitening, FEC, interleaving, CRC и отображение символов](lora-phy-coding.md).

---

## 1. Основные параметры LoRa

LoRa-символ представляет собой циклически сдвинутый chirp. Для spreading factor
`SF` существует:

```text
N = 2^SF
```

возможных положений/значений символа.

Основные параметры:

| Параметр | Назначение |
|---|---|
| `SF` | spreading factor, обычно SF5...SF12 для современных Semtech LoRa IC |
| `BW` | полоса chirp, например 62.5, 125, 250 или 500 кГц |
| `CR` | coding rate payload: 4/5, 4/6, 4/7 или 4/8 |
| `Fc` | центральная RF-частота |
| `PreambleLength` | программируемое число базовых preamble upchirp |
| `SyncWord` | идентификатор/фильтр семейства сети |
| `HeaderType` | explicit или implicit |
| `PayloadLength` | число байт payload |
| `PayloadCRC` | наличие 16-битного CRC payload |
| `LDRO/DE` | low-data-rate optimization для длинных символов |

### 1.1. Chip rate и symbol time

Для LoRa chip rate численно равен полосе:

```text
Rchip = BW
```

Один символ содержит `2^SF` chips, поэтому:

```text
Tsym = 2^SF / BW
Rsym = BW / 2^SF
```

Например, для используемого в проекте режима `SF7 / BW125`:

```text
N    = 128 chips
Tsym = 128 / 125000 = 1.024 ms
Rsym = 976.5625 symbols/s
```

Для `SF12 / BW125`:

```text
Tsym = 4096 / 125000 = 32.768 ms
```

Рост SF повышает чувствительность и энергетическую эффективность приёма, но
резко увеличивает длительность символа и Time-on-Air.

### 1.2. Приближённая полезная битовая скорость

Без учёта preamble/header/CRC и блочной упаковки:

```text
Rb ~= SF * BW / 2^SF * 4/(4+CR)
```

где в формуле `CR = 1..4` соответствует:

| CR field | Coding rate | Коэффициент |
|---:|---:|---:|
| 1 | 4/5 | 4/5 |
| 2 | 4/6 | 4/6 |
| 3 | 4/7 | 4/7 |
| 4 | 4/8 | 4/8 |

Для `SF7 / BW125 / CR=4/5` получается около `5.47 kbit/s` до учёта
пакетного overhead.

---

## 2. Структура LoRa-сигнала в эфире

Удобное инженерное представление стандартного Semtech-совместимого LoRa кадра:

```text
                  PREAMBLE / SYNCHRONIZATION
┌──────────────────────┬──────────────────┬──────────────────────┐
│ Npre base upchirps   │ 2 sync upchirps │ 2.25 downchirps SFD  │
└──────────────────────┴──────────────────┴──────────────────────┘
                                                               │
                                                               ▼
┌──────────────────────────┬──────────────────────┬─────────────┐
│ PHDR + PHDR checksum     │ Payload              │ Payload CRC │
│ explicit mode only       │ 0...255 bytes        │ optional    │
└──────────────────────────┴──────────────────────┴─────────────┘
```

В формулах Semtech длительность preamble обычно записывается компактно:

```text
Tpreamble = (Npre + 4.25) * Tsym
```

То есть два sync-symbol и `2.25` downchirp входят в дополнительные `4.25`
символа.

### Важная терминология

Если в настройках трансивера указано:

```text
PreambleLength = 8
```

это обычно означает **8 программируемых базовых upchirp**, а не 8 символов
полной преамбулы в эфире.

Фактическая длительность для типичного случая:

```text
8 + 4.25 = 12.25 symbols
```

Для `SF7 / BW125`:

```text
Tpreamble = 12.25 * 1.024 ms = 12.544 ms
```

---

## 3. Базовые preamble upchirp

Начало кадра содержит `Npre` одинаковых reference upchirp. Их задачи:

1. обнаружение присутствия LoRa/CSS сигнала;
2. грубое определение границ символов;
3. оценка carrier-frequency offset (CFO);
4. оценка sample/timing offset;
5. подготовка автоматической регулировки усиления и синхронизации приёмника.

Часто используется `Npre = 8`, но длина программируется и может быть увеличена,
например для duty-cycled receiver, которому нужно больше времени для обнаружения
пакета.

Передатчик и приёмник должны иметь совместимые ожидания относительно preamble.
Слишком короткая преамбула ухудшает вероятность acquisition, особенно при низком
SNR, большом CFO или периодически включаемом RX.

---

## 4. Sync word

После базовых preamble upchirp передаются два специальных upchirp, кодирующих
**sync word**.

Sync word используется как PHY-фильтр: приёмник может отвергнуть сигнал с
неподходящим сетевым идентификатором ещё до полного декодирования payload.

Часто встречаются значения:

| Sync word | Назначение |
|---|---|
| `0x12` | private/proprietary LoRa profile |
| `0x34` | public/LoRaWAN-compatible profile |

Точное регистровое представление sync word различается между поколениями
Semtech IC. Поэтому при сравнении SX127x, SX126x, LR11xx, SDR и лабораторного
генератора нужно сравнивать **результирующие два sync-symbol**, а не только
число, записанное в конкретный регистр.

### 4.1. Представление sync word в модели проекта

Semtech-совместимая модель проекта использует распространённое отображение
однобайтного sync word в два CSS symbol:

```text
sync0 = high_nibble * 8
sync1 = low_nibble  * 8
```

Например, для `0x34`:

```text
high nibble = 3 -> symbol 24
low  nibble = 4 -> symbol 32
```

Эта конвенция используется в MATLAB/Simulink detector проекта и согласуется с
Semtech-совместимыми SDR реализациями. При работе с конкретным RFIC следует
дополнительно учитывать его register/API encoding.

---

## 5. SFD: Start-of-Frame Delimiter

После sync word передаются downchirp, образующие SFD:

```text
2 full downchirps + 1/4 downchirp = 2.25 symbols
```

Переход от upchirp к downchirp даёт приёмнику сильную временную метку и позволяет
уточнить начало области header/payload.

Особенно важна последняя четверть символа: после SFD начало первой data/header
сетки смещено на четверть LoRa-символа относительно свободно идущей сетки
preamble. Для `SF` это соответствует сдвигу порядка:

```text
2^(SF-2) bins
```

Именно поэтому в packet decoder проекта присутствует ограниченный поиск
quarter-symbol bin adjustment.

---

## 6. Explicit и implicit header

LoRa PHY поддерживает два режима.

### 6.1. Explicit Header Mode

В explicit mode перед payload передаётся PHY header (`PHDR`). Он сообщает
приёмнику:

- длину payload в байтах;
- coding rate payload;
- присутствует ли payload CRC.

Сам header имеет собственную checksum и передаётся с максимальной защитой
`CR = 4/8`, независимо от CR последующего payload.

Это основной режим, когда параметры пакета заранее неизвестны приёмнику.

### 6.2. Implicit Header Mode

В implicit mode PHY header в эфире отсутствует.

Приёмник обязан **заранее знать**:

- длину payload;
- coding rate;
- включён ли payload CRC;
- остальные параметры PHY.

Преимущество — меньший overhead. Недостаток — TX и RX должны быть заранее
согласованы. Такой режим удобен для закрытого протокола с фиксированным форматом
кадра.

---

## 7. Формат explicit PHY header

Публичная документация Semtech определяет смысл полей header, а точная
битовая упаковка ниже соответствует Semtech-compatible reverse-engineered
формату, который реализован и regression-проверяется в этом репозитории.

До FEC/interleaving header представлен **пятью 4-битными nibble**:

```text
H0  H1  H2  H3  H4
```

### 7.1. Поля

```text
H0 = PayloadLength[7:4]
H1 = PayloadLength[3:0]
H2 = 2*CR + PayloadCrcPresent
H3/H4 = 5-bit header checksum + reserved zeros
```

В терминах битов:

| Информация | Размер |
|---|---:|
| Payload length | 8 бит |
| Payload coding-rate field | 3 бита |
| Payload CRC present | 1 бит |
| Header checksum | 5 бит |
| Reserved/padding в 5-nibble представлении | 3 бита |
| **Итого до FEC** | **20 бит** |

`H2` принимает значения:

| Payload CR | CRC off | CRC on |
|---|---:|---:|
| 4/5 | `0x2` | `0x3` |
| 4/6 | `0x4` | `0x5` |
| 4/7 | `0x6` | `0x7` |
| 4/8 | `0x8` | `0x9` |

Header является частью **первого coding block**. Для обычных SF7...SF12 этот
первый блок использует reduced-rate mapping и всегда даёт **8 LoRa symbols** с
защитой 4/8. В свободные позиции первого блока могут попадать первые nibble
payload/CRC в зависимости от SF и длины данных.

Для специальных SF5/SF6 режимов современных SX126x существуют отличия первого
блока/фрейминга; они уже отдельно покрываются тестами packet model проекта и не
следует механически переносить правила SF7...SF12 на SF5/SF6.

---

## 8. Payload

В explicit header поле длины однобайтное, поэтому логическая длина PHY payload
кодируется в диапазоне `0...255` байт. У конкретных RFIC FIFO/driver API может
иметь 256-байтный буфер, но это не следует путать с полем `PayloadLength`.

LoRaWAN дополнительно ограничивает максимально допустимый MAC payload по
региону и data rate, поэтому максимальный LoRaWAN payload обычно меньше
теоретического PHY предела.

В нашем Semtech-compatible тракте payload проходит последовательность:

```text
payload bytes
    ↓
payload CRC calculation (если включён)
    ↓
whitening payload bytes
    ↓
split into low-nibble-first order
    ↓
FEC 4/(4+CR)
    ↓
diagonal interleaving
    ↓
Gray/inverse-Gray-compatible symbol mapping
    ↓
CSS cyclic shift
    ↓
LoRa chirps
```

Точные whitening/FEC/interleaving/CRC правила описаны в
[`lora-phy-coding.md`](lora-phy-coding.md).

---

## 9. Forward Error Correction

Каждый 4-битный data nibble расширяется до `4 + CR` coded bits:

| CR | Код | Coded bits на 4 data bits | Overhead |
|---:|---:|---:|---:|
| 1 | 4/5 | 5 | +25% |
| 2 | 4/6 | 6 | +50% |
| 3 | 4/7 | 7 | +75% |
| 4 | 4/8 | 8 | +100% |

Больший CR даёт больше redundancy и обычно повышает устойчивость к ошибкам, но
увеличивает число LoRa-symbol и Time-on-Air.

Header в explicit mode всегда использует наиболее защищённый первый блок 4/8;
payload использует CR из PHDR.

---

## 10. Interleaving и отображение в CSS-symbol

После FEC биты переставляются диагональным interleaver. Цель — распределить
ошибку одного LoRa-symbol по нескольким FEC codeword.

Затем interleaved label преобразуется в индекс циклического сдвига chirp.
Каждый LoRa-symbol при SF=`SF` имеет индекс:

```text
0 ... 2^SF - 1
```

После dechirp идеальный символ превращается в узкий FFT peak. Поэтому типичный
приёмный тракт имеет вид:

```text
IQ
 ↓
CFO/timing correction
 ↓
dechirp
 ↓
FFT
 ↓
symbol/bin decision
 ↓
Gray restoration
 ↓
deinterleaving
 ↓
FEC decode
 ↓
dewhitening
 ↓
CRC/header validation
```

---

## 11. CRC и checksum: три разных механизма

В LoRa/LoRaWAN легко перепутать несколько проверок целостности.

### 11.1. PHDR checksum

- относится только к explicit PHY header;
- в Semtech-compatible формате имеет 5 бит;
- позволяет отвергнуть ошибочно декодированный header до обработки payload.

### 11.2. LoRa payload CRC

- опциональный PHY CRC;
- 16 бит;
- относится к payload LoRa PHY;
- обнаруживает остаточные ошибки после FEC;
- **не является криптографической аутентификацией**.

### 11.3. LoRaWAN MIC

- часть LoRaWAN `PHYPayload`;
- имеет другую задачу и рассчитывается на MAC/сетевом уровне;
- проверяет целостность/подлинность LoRaWAN сообщения;
- не заменяется LoRa PHY CRC.

Таким образом, пакет может одновременно иметь:

```text
PHDR checksum + LoRa payload CRC + LoRaWAN MIC
```

и это три разные проверки.

---

## 12. LoRa PHY и LoRaWAN frame

Если поверх LoRa PHY используется LoRaWAN, то содержимое LoRa PHY payload
представляет LoRaWAN `PHYPayload`:

```text
LoRa PHY
┌───────────────────────────────────────────────────────────────┐
│ Preamble | PHDR |                Payload             | CRC?  │
│                  ┌─────────────────────────────────┐          │
│                  │ LoRaWAN PHYPayload              │          │
│                  │ MHDR | MACPayload | MIC         │          │
│                  └─────────────────────────────────┘          │
└───────────────────────────────────────────────────────────────┘
```

Упрощённо LoRaWAN:

```text
PHYPayload = MHDR (1 byte) | MACPayload (variable) | MIC (4 bytes)
```

Внутри `MACPayload` находятся `FHDR`, необязательный `FPort` и `FRMPayload`.
Полное описание LoRaWAN L2 выходит за рамки этого файла.

Критически важно: **LoRa PHY header не является LoRaWAN MHDR**.

---

## 13. Low Data Rate Optimization (LDRO / DE)

При длинных LoRa-symbol влияние рассогласования опорных генераторов и времени
становится значительным. Для таких режимов используется low-data-rate
optimization.

В формулах Time-on-Air:

```text
DE = 1  -> LDRO enabled
DE = 0  -> LDRO disabled
```

На практике LDRO особенно важен для длинных symbol time, например типичных
`SF11/SF12 @ BW125` режимов. Точное правило включения следует брать из
документации/driver конкретного Semtech IC, а не определять только по номеру SF.

LDRO меняет effective spreading factor для coding/interleaving и поэтому должен
совпадать на TX и RX.

---

## 14. Расчёт Time-on-Air

### 14.1. Symbol time

```text
Tsym = 2^SF / BW
```

### 14.2. Preamble

```text
Tpreamble = (Npre + 4.25) * Tsym
```

### 14.3. Число payload symbols

Распространённая Semtech формула:

```text
Npayload = 8 + max(
    ceil(
        (8*PL - 4*SF + 28 + 16*CRC - 20*IH)
        / (4*(SF - 2*DE))
    ) * (CR + 4),
    0
)
```

где:

- `PL` — payload length, bytes;
- `SF` — spreading factor;
- `CRC = 1`, если payload CRC включён, иначе `0`;
- `IH = 0` для explicit header, `1` для implicit;
- `DE = 1` при LDRO, иначе `0`;
- `CR = 1...4` для 4/5...4/8.

Payload duration:

```text
Tpayload = Npayload * Tsym
```

Полный Time-on-Air:

```text
ToA = Tpreamble + Tpayload
```

### 14.4. Пример: SF7 / BW125 / CR4/5 / 16 bytes

Пусть:

```text
SF   = 7
BW   = 125 kHz
CR   = 1        -> 4/5
PL   = 16 bytes
Npre = 8
CRC  = 1
IH   = 0        -> explicit header
DE   = 0
```

Тогда:

```text
Tsym      = 1.024 ms
Tpreamble = 12.544 ms
Npayload  = 38 symbols
Tpayload  = 38.912 ms
ToA       = 51.456 ms
```

Это хороший ориентир для проверки собственного packet generator и Inspector.

---

## 15. Что должен делать полноценный LoRa PHY receiver

Практический порядок приёма:

1. выделить нужный RF channel и BW;
2. найти последовательность одинаковых preamble upchirp;
3. оценить coarse/fine CFO;
4. оценить symbol timing / sample offset;
5. проверить два sync-symbol;
6. обнаружить `2.25`-symbol SFD;
7. учесть quarter-symbol сдвиг сетки;
8. dechirp + FFT каждого data symbol;
9. получить CSS-bin/symbol decisions;
10. восстановить Gray mapping;
11. deinterleave первый block;
12. декодировать header на CR4/8 и проверить PHDR checksum;
13. получить PL/CR/CRC settings;
14. deinterleave и FEC-decode payload blocks;
15. dewhiten payload;
16. проверить LoRa payload CRC;
17. если это LoRaWAN — отдельно разобрать MHDR/MACPayload и проверить MIC.

Этот список удобно использовать как checklist для MATLAB -> Simulink -> HDL
реализации.

---

## 16. Что уже соответствует этому формату в репозитории

В `main` уже реализованы и протестированы:

- Semtech-compatible explicit-header encode/decode;
- 5-nibble PHDR и его checksum;
- payload whitening;
- FEC 4/5...4/8;
- diagonal interleaving/deinterleaving;
- Gray/CSS-bin mapping;
- LoRa-compatible payload CRC;
- стандартная preamble/sync/SFD обработка в on-air receiver;
- special handling для SF5/SF6;
- приём и декодирование реальных SX1262 пакетов.

Отдельный исследовательский `preamble_waveform` (`8 up + 2 down`) используется
для алгоритмических экспериментов acquisition и **не является полным стандартным
LoRa preamble**. Его нельзя смешивать со стандартным packet framing.

HDL-ветка проекта дополнительно развивает TX waveform generation; до заявления
о полном LoRa transmitter необходимо отдельно подтвердить на HDL всю цепочку:

```text
standard preamble -> sync word -> 2.25 SFD -> PHDR -> coded payload -> CRC
```

---

## 17. Практические признаки корректного LoRa кадра на спектрограмме

Для исправного кадра обычно видны:

1. серия одинаковых положительно наклонённых upchirp;
2. два смещённых sync upchirp;
3. резкий переход к downchirp SFD;
4. после SFD — последовательность data chirp с разными циклическими сдвигами.

Для цифровой верификации полезно проверять не только картинку, но и:

- точное число samples на символ;
- continuity фазового аккумулятора;
- правильность I/Q polarity;
- правильный sync word;
- длительность `2.25` SFD;
- quarter-symbol alignment первого header symbol;
- header checksum;
- decoded payload length и CR;
- payload CRC;
- EVM/correlation относительно MATLAB golden.

---

## 18. Источники и граница спецификации

LoRa PHY является технологией Semtech; LoRaWAN L2 стандартизован LoRa Alliance.
Часть низкоуровневых деталей LoRa PHY исторически документировалась через
datasheets и была уточнена исследовательскими reverse-engineering работами.
Поэтому в проекте различаются:

1. **официально документированные параметры Semtech** — SF/BW/CR, preamble
   length, explicit/implicit header semantics, payload CRC, Time-on-Air;
2. **Semtech-compatible bit-level conventions**, подтверждённые реальными
   SX1262/LR1121 записями и golden tests проекта — whitening, header checksum,
   bit order, interleaving и CSS label mapping.

Основные ссылки:

- [Semtech SX1262 product page and current SX1261/SX1262 datasheet](https://www.semtech.com/products/wireless-rf/lora-connect/sx1262)
- [Semtech LoRa FAQ / troubleshooting](https://www.semtech.com/design-support/faq/faq-lora)
- [Semtech LoRaWAN FAQ: explicit PHY header fields](https://www.semtech.com/design-support/faq/faq-lorawan)
- [Semtech AN1200.22: LoRa Modulation Basics](https://www.semtech.com/products/wireless-rf/lora-connect/sx1276)
- [Semtech LoRa Calculator](https://calculator.semtech.com/)
- [LoRa and LoRaWAN: A Technical Overview, Semtech](https://lora-developers.semtech.com/uploads/documents/files/LoRa_and_LoRaWAN-A_Tech_Overview-Downloadable.pdf)
- [Marquet, Montavont, Papadopoulos: LoRa PHY reverse engineering](https://doi.org/10.1016/j.comcom.2020.02.034)
- [EPFL gr-lora_sdr](https://github.com/tapparelj/gr-lora_sdr)

Для реализации в этом репозитории первичными executable references остаются
MATLAB/Python golden tests и реальные RF captures; текстовая документация должна
соответствовать им, а не заменять их.
