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
7. Жёсткие FFT-решения проходят Gray mapping, deinterleaving, Hamming decode,
   dewhitening и CRC.

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

## Весь набор

```matlab
addpath examples
results = decode_reference_sweep(d, ...
    OutputCsv=fullfile(d, "decode-summary.csv"));
```

В текущем наборе сквозной decode успешен для 24 из 27 автоматически выбранных
посылок, включая SF5, SF7…SF12, BW 62,5/125/250 кГц, CR 4/5…4/8, длины
12…220 байт, CRC off, sync word `0x34` и inverted IQ. Два файла дают валидный
header, но не проходят payload CRC (`sf6-bw125`, `sf7-power-m9`); они нужны для
разработки soft decisions. У BW500 пока неустойчив первичный поиск, потому что
сигнал занимает практически всю полезную полосу записи при Fs=1 Мвыб/с.

## Что показывает график

- спектрограмма увеличена до одной посылки и размечает preamble, sync, SFD и
  payload;
- stem-график показывает hard FFT bin каждого символа;
- confidence равен отношению энергии максимального FFT-bin к полной энергии;
- текстовый блок показывает header, CFO, CRC, hex и печатный ASCII payload.

## Связь с BER/PER

Эта функция анализирует один пакет и не подменяет BER-эксперимент. Для
эфирного BER нужен известный payload sequence, декодирование **всех** пакетов и
раздельные счётчики:

```text
pre-FEC BER = ошибочные codeword bits / все принятые codeword bits
payload BER = ошибочные payload bits / все переданные payload bits
PER         = пакеты с acquisition/header/CRC failure / все передачи
```

Пакет с невалидным CRC учитывается в PER даже если часть байтов выглядит
правдоподобно. Следующий этап — multi-packet detector, soft FFT metrics и
автоматическое сопоставление payload с TX-журналом; после этого сохранённый
sweep можно использовать как воспроизводимый PER-регрессионный набор.
