# Декодирование эфирного LoRa-пакета в MATLAB

`lora_phy.receive_lora_packet` превращает сохранённую IQ-запись в проверенный
payload. В отличие от общего Inspector, функция получает известные BW и SF:
это соответствует реальному приёмнику, которому профиль канала задают до
начала приёма.

## Цепочка обработки

1. При необходимости выполняется conjugation для inverted IQ и перенос
   ожидаемой несущей в ноль.
2. Энергетический детектор находит сильнейшую посылку; для широкополосного
   граничного случая предусмотрен поиск повторяемых dechirped-пиков.
3. По upchirp уточняются начало символа и CFO.
4. Проверяются программируемая преамбула и два sync-символа. Каждый nibble
   sync word передаётся как `nibble * 8` при любом SF.
5. Начало данных вычисляется после двух sync-symbol и SFD `2.25 downchirp`.
   Для SX126x SF5/SF6 учитываются ещё два upchirp после SFD.
6. В окрестности границы перебираются sample offsets. Предпочитается кандидат
   с валидными header checksum и payload CRC.
7. Для каждого символа сохраняются метрики всех FFT bins. Max-log разность
   лучших гипотез `bit=0`/`bit=1` образует LLR, который проходит Gray mapping и
   diagonal deinterleaving.
8. Выполняются параллельные hard и soft FEC decode. Soft-результат выбирается,
   если он проходит CRC или hard-результат уже неуспешен.

## Один файл

```matlab
cd model/matlab
d = "../../captures/reference/2026-08-03-heltec-v43-zynqsdr-mode-sweep";
[iq, ~] = lora_phy.load_iq_capture(fullfile(d, "sf7-bw125.cf32"), "cf32");

rx = lora_phy.receive_lora_packet(iq, 1e6, 125e3, 7, ...
    PreambleSymbols=12, SyncWord=hex2dec("12"), ...
    ExpectedCarrierOffsetHz=-250e3);

assert(rx.success)
disp(rx.decoded.header)
disp(rx.decoded.payload.')
lora_phy.visualize_lora_packet(iq, 1e6, rx);
```

У контрольной записи декодируются 32 байта, ASCII-префикс `ZLP1`, sequence 7,
CR 4/5 и включённый payload CRC. Header checksum и payload CRC валидны.

![Реальный SX1262-пакет после демодуляции](../images/lora-packet-demodulation-sx1262.png)

## Все пакеты в одной записи

```matlab
set = lora_phy.receive_lora_packets(iq, 1e6, 125e3, 7, ...
    PreambleSymbols=12, SyncWord=hex2dec("12"), ...
    ExpectedCarrierOffsetHz=-250e3);

for k = 1:numel(set.packets)
    fprintf("t=%.6f s, sequence=%u\n", ...
        set.packets(k).preambleStartSeconds, ...
        typecast(set.packets(k).decoded.payload(5:8), "uint32"));
end
```

Activity detector разделяет передачи по паузам, а каждый сегмент проходит
полный packet receiver. На контрольной записи находятся все три пакета:
sequence 7, 8 и 9.

## BER/PER по всему набору

```matlab
addpath examples
report = evaluate_reference_sweep(d, OutputDirectory=d);
```

Функция читает `manifest.json`, восстанавливает ожидаемый counter payload из
`TX seq/len/start_ms`, сопоставляет его с приёмами сначала по sequence, затем по
времени, и создаёт:

- `packet-performance.csv` — одна строка на передачу;
- `case-performance.csv` — одна строка на режим;
- `performance-summary.json` — агрегированные счётчики.

Текущий воспроизводимый результат для 70 передач:

| Метрика | Результат |
|---|---:|
| Acquisition valid | 68/70 |
| Header valid | 66/70 |
| Payload совпал | 60/70 |
| Hard success | 59/70 |
| Soft success | 61/70 |
| Дополнительно восстановлено soft decoder | 2 |
| PER | 14,29% |
| Pre-FEC BER по доступным codeword bits | 711/30505 = 2,33% |
| BER среди сравнимых payload | 85/21728 = 0,39% |
| Консервативный payload BER | 1109/22752 = 4,87% |

Локальное окно вокруг каждого activity-run устранило ложный захват третьего
SF5-сегмента: acquisition теперь 3/3, один payload проходит CRC и совпадает с
TX. Оставшаяся acquisition-проблема — BW500 при Fs=1 Мвыб/с. Для двух SF5 и
нескольких слабых/коротких режимов пакет находится, но отклоняется header, CRC
или сравнением с TX payload.

## Что показывает график

- спектрограмма увеличена до одной посылки и размечает preamble, sync, SFD и
  payload;
- stem-график показывает hard FFT bin каждого символа;
- confidence равен отношению энергии максимального FFT-bin к полной энергии;
- текстовый блок показывает header, CFO, CRC, hex и печатный ASCII payload.

## Связь с BER/PER

Отчёт использует известный payload и декодирует все найденные пакеты. Метрики
определены раздельно:

```text
pre-FEC BER = ошибочные raw codeword bits / доступные raw codeword bits
compared payload BER = ошибки / bits у payload правильной длины
conservative payload BER = ошибки с полным штрафом за недекодированный пакет
PER = acquisition/header/CRC/payload mismatch / все подтверждённые TX
```

Пакет с невалидным CRC учитывается в PER даже если часть байтов выглядит
правдоподобно. При `CRC off` packet error всё равно обнаруживается сравнением с
известным TX payload. Это регрессионная характеристика конкретного смешанного
sweep, а не калиброванная sensitivity-кривая: для неё потребуется отдельная
серия с контролируемым SNR/мощностью и значительно большим числом пакетов.
