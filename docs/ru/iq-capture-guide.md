# Запись пакетов SX1262 с RTL-SDR и PlutoSDR

[English version](../iq-capture-guide.md)

Первая цель записи — не sensitivity и не ToA. Нужна воспроизводимая запись для
проверки PHY, где известны все переданные байты и настройки LoRa. PlutoSDR
используется как основной инженерный источник IQ, RTL-SDR — как быстрая
независимая проверка.

## Рекомендуемый порядок

1. После получения Heltec проверить маркировку, региональную RF-версию, антенну
   и установленную прошивку.
2. Передавать детерминированные point-to-point LoRa packets, не LoRaWAN.
3. Сначала сделать короткую OTA-запись на минимальной мощности.
4. Проверить частоту, период пакетов, gain и отсутствие clipping.
5. Записать один и тот же firmware одновременно/последовательно RTL-SDR и
   PlutoSDR.
6. Сохранить raw IQ и metadata без редактирования.
7. Только после успешного OTA перейти к кабелю с рассчитанным attenuation.

Heltec WiFi LoRa 32 V4 построена на ESP32-S3 и SX1262. Производитель заявляет
LoRa TX power `28 ± 1 dBm`. Нельзя ориентироваться на мощность предыдущих
версий или напрямую соединять плату с SDR. В худшем случае после 30 dB
аттенюатора останется около −1 dBm без учёта потерь кабеля.

## Детерминированный пакет Heltec

Начать следует с актуального официального примера Heltec point-to-point LoRa
TX. LoRaWAN пока не нужен: join, encryption, counters и network fields усложнят
первую проверку PHY.

Начальная конфигурация:

| Параметр | Значение |
|---|---:|
| Carrier | разрешённая частота для варианта платы и региона |
| Bandwidth | 125 кГц |
| SF | 7 |
| CR | 4/5 (`CR=1`) |
| Preamble | 8 symbols |
| Header | explicit |
| Payload CRC | enabled |
| IQ inversion | disabled |
| Sync word | записать точное числовое значение |
| Payload | 16 бинарных bytes фиксированной структуры |
| TX power | минимальная стабильная настройка |

Рекомендуемый payload:

```text
offset  size  value
0       2     5A 4C                 magic "ZL"
2       1     01                    версия схемы payload
3       1     00                    flags
4       4     sequence number       uint32 little endian
8       4     ESP timer             младшие uint32 little endian
12      4     A5 5A 3C C3           фиксированный pattern
```

На каждую передачу выводить в serial log:

- UTC host time;
- sequence number и полный payload hex;
- ESP timer и TX result;
- frequency, BW, SF, CR;
- header mode, CRC, preamble, sync word, IQ inversion;
- TX-power setting.

Sequence number позволяет сопоставить RF-burst с конкретным пакетом, даже если
запись началась в середине серии.

Интервал должен разделять пакеты и соответствовать местным правилам спектра и
получившемуся airtime. Период 1 с удобен только там, где он разрешён; иначе
использовать больший период или экранированный/кабельный тракт с достаточным
ослаблением.

## План настройки приёмника

У direct-conversion receiver обычно есть DC-компонента в центре спектра. Поэтому
первую запись лучше делать со смещённой настройкой.

Пример, если разрешённый carrier равен `868.100 MHz`:

```text
частота SDR       = 868.350 MHz
LoRa в записи     = -250 kHz
цифровой сдвиг    = +250 kHz
```

Для Pluto использовать 1 MS/s, для RTL-SDR — 1.024 MS/s. Это оставляет запас
вокруг канала 125 кГц. Перенос в ноль в MATLAB:

```matlab
n = (0:numel(iq)-1).';
iqBaseband = iq .* exp(1j*2*pi*250e3*n/sampleRateHz);
```

Знак определяется как `Fcenter - Fsignal`; нельзя угадывать его по waterfall.

## Запись RTL-SDR

RTL-SDR — receive-only и удобен для быстрого подтверждения RF burst. `rtl_sdr`
сохраняет headerless unsigned 8-bit interleaved `I,Q`, поэтому метаданные
обязательны.

1. Подключить правильную RX-антенну и разнести передатчик/приёмник на несколько
   метров.
2. Проверить устройство:

   ```powershell
   rtl_test -t
   ```

3. Записать 30 секунд с ручным начальным gain:

   ```powershell
   rtl_sdr -d 0 -f 868350000 -s 1024000 -g 20 -p 0 -n 30720000 captures/heltec-sf7-cr1-rtl.cu8
   ```

4. Немедленно вычислить checksum:

   ```powershell
   Get-FileHash -Algorithm SHA256 captures/heltec-sf7-cr1-rtl.cu8
   ```

5. Скопировать
   [`experiments/templates/phy-capture.yaml`](../../experiments/templates/phy-capture.yaml)
   в `experiments/runs/` и записать command line, tuner, serial, gain, PPM,
   ожидаемый и фактический размер, checksum.

При 1.024 MS/s 30 секунд содержат 30 720 000 комплексных samples и занимают
61 440 000 bytes. Если размер отличается, записать фактическое число samples, а
не изменять raw file.

Чтение в MATLAB:

```matlab
file = fopen("captures/heltec-sf7-cr1-rtl.cu8", "r");
raw = fread(file, Inf, "uint8=>double");
fclose(file);
iq = complex(raw(1:2:end)-127.5, raw(2:2:end)-127.5) / 127.5;
```

Сделать несколько коротких записей, например с gain около 10, 20 и 30 dB.
Выбрать минимальный manual gain, при котором пакет выше noise floor, но sample
histogram не упирается в крайние коды. Для эталонной записи AGC не использовать.
Сначала оставить `-p 0`, оценить CFO по преамбуле, а применённую позже PPM
correction обязательно записывать.

## Запись PlutoSDR

Pluto — основной источник: AD936x предоставляет sample rate, RF bandwidth, LO
и manual gain через libiio. Установить IIO driver/runtime и Python bindings:

```powershell
python -m pip install pyadi-iio pylibiio
```

Проверить подключение `iio_info -s`, затем выполнить:

```powershell
python tools/capture_pluto.py `
  --uri ip:192.168.2.1 `
  --signal-frequency 868100000 `
  --center-frequency 868350000 `
  --sample-rate 1000000 `
  --rf-bandwidth 1000000 `
  --gain 20 `
  --samples 4194304 `
  --count 5 `
  --output captures/heltec-sf7-cr1-pluto
```

Каждый файл содержит около 4.19 с непрерывных complex samples в формате
little-endian float32 `I,Q`. Между файлами возможны разрывы. Скрипт отбрасывает
warm-up buffers, использует manual gain, читает фактические настройки обратно и
считает SHA-256 каждого `.cf32`.

Чтение одного файла в MATLAB:

```matlab
file = fopen("captures/heltec-sf7-cr1-pluto/pluto-...-000.cf32", "r", "ieee-le");
raw = fread(file, Inf, "single=>single");
fclose(file);
iq = complex(raw(1:2:end), raw(2:2:end));
```

Не объединять пять файлов в якобы непрерывную запись. Каждый buffer
обрабатывается отдельно, пока внешний trigger или streaming test не докажет
непрерывность между границами.

## Критерии качества

Запись принимается, только если зафиксировано:

- LoRa burst находится на ожидаемом signed offset;
- видны или декодируются не менее 20 известных sequence numbers;
- histogram I/Q не накапливается на числовых границах;
- известны manual gain, LO, sample rate и bandwidth;
- CFO по преамбуле стабилен между пакетами;
- есть noise-only интервалы до и после пакетов;
- размер и SHA-256 совпадают с metadata;
- serial log Heltec перекрывает интервал записи;
- задокументированы антенны, расстояние и ориентация либо полный cable path.

Нужно сохранить weak, medium и strong-but-unclipped capture, а не только лучший.
Они выявят проблемы AGC, clipping, quantization и thresholds.

## OTA и кабель

Сначала использовать OTA: минимальная TX power, правильные антенны, физическое
разнесение и короткие серии.

Для кабеля имеющегося 30 dB attenuator недостаточно. Нужно проверить настройку
мощности Heltec и maximum safe input обоих SDR, рассчитать worst-case power,
добавить fixed attenuation и при необходимости DC block. Начинать с максимального
безопасного ослабления и уменьшать его документированными шагами. Нельзя
переключать включённый передатчик без согласованной нагрузки.

## Матрица после первого успешного пакета

| Run | Приёмник | SF | CR | Цель |
|---|---|---:|---:|---|
| 1 | RTL-SDR | 7 | 4/5 | независимое подтверждение RF |
| 2 | PlutoSDR | 7 | 4/5 | основной MATLAB compatibility vector |
| 3 | PlutoSDR | 7 | 4/8 | проверка FEC/interleaver |
| 4 | PlutoSDR | 8 | 4/5 | масштабирование symbol duration |
| 5 | PlutoSDR | 7 | 4/5 | weak signal |
| 6 | PlutoSDR | 7 | 4/5 | strong, но без clipping |

В одном run меняется только одна переменная. Нельзя одновременно менять SF,
CR, frequency, gain и payload.

## Источники

- [Heltec WiFi LoRa 32 V4](https://docs.heltec.org/en/node/esp32/wifi_lora_32/index.html)
- [Официальная библиотека Heltec](https://github.com/HelTecAutomation/Heltec_ESP32)
- [PlutoSDR quick start](https://wiki.analog.com/university/tools/pluto/users/quick_start)
- [pyadi-iio Pluto](https://analogdevicesinc.github.io/pyadi-iio/devices/adi.ad936x.html)
- [libiio receive workflow](https://wiki.analog.com/university/tools/pluto/controlling_the_transceiver_and_transferring_data)
- [`rtl_sdr` reference](https://manpages.debian.org/testing/rtl-sdr/rtl_sdr.1.en.html)
