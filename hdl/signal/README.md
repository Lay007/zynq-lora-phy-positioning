# HDL IQ-записи и 5 контрольных точек LoRa TX

Каталог `hdl/signal` предназначен для проверки IQ-потока, сформированного HDL-трактом LoRa/CSS, в MATLAB-приложении **LoRa PHY Inspector**.

Бинарные `*.pcm` являются **воспроизводимыми артефактами симуляции**, а не исходными файлами проекта. Они не должны храниться в Git. Source of truth: HDL + self-checking testbench + MATLAB golden model.

## Быстрый ответ: какой параметр говорит «всё хорошо»

В Inspector совокупный результат выводится крупно:

```text
OVERALL / ИТОГ: PASS | WARN | FAIL | NOT VERIFIED
```

Для точек с полноценным golden reference (`Stage 1` и `Stage 2`) одного значения корреляции недостаточно. Решение принимается по набору условий:

```text
EVM <= 1 %
correlation >= 0.999
RMS phase error <= 1 degree
```

Структурные ошибки, например неправильное число отсчётов, дают `FAIL`. Если структура верна, но waveform не проходит строгие golden-пороги, результат `WARN`.

`NOT VERIFIED` означает, что Inspector распознал контрольную точку, но в репозитории пока нет точного executable golden для production FIR/CIC/mixer. Это намеренно: неподтверждённая точка не должна показывать ложный `PASS`.

## Пять контрольных точек TX

Тракт, который проверяем:

```text
[1] chirp generator
        │  Fs = 2.000 MS/s
        v
[2] package generator
        │  Fs = 2.000 MS/s
        v
[3] FIR / rational resampler 24/25
        │  Fs = 1.920 MS/s
        v
[4] CIC interpolator x32
        │  Fs = 61.440 MS/s
        v
[5] frequency shifter / NCO
           Fs = 61.440 MS/s
```

### Stage 1 — отдельный chirp

Проверяется один конкретный LoRa/CSS-символ.

Для текущей конфигурации:

```text
SF7
BW = 125 kHz
Fs = 2.000 MS/s
L = Fs/BW = 16 samples/chip
Ns = 2^7 * 16 = 2048 complex samples
```

Ожидаемый размер CI16-файла:

```text
2048 * 4 = 8192 bytes
```

Inspector проверяет:

- точное число отсчётов;
- MATLAB golden waveform для указанного `h` и направления;
- EVM;
- normalized correlation;
- RMS/max phase error;
- peak normalized sample error.

Примеры имён:

```text
hdl_sf7_bw125k_fs2000k_chirp-h0-up.pcm
hdl_sf7_bw125k_fs2000k_chirp-h17-up.pcm
hdl_sf7_bw125k_fs2000k_chirp-h64-down.pcm
```

Имя `..._chirp.pcm` запрещено: оно не задаёт `h` и направление.

### Stage 2 — текущий package stream

Это проверка **всей последовательности**, формируемой текущим `formiration_package`, а не только первого chirp.

Текущий HDL-контракт:

```text
6 x h=0 upchirp
h=5   upchirp
h=17  upchirp
h=64  downchirp
h=127 upchirp
```

Всего:

```text
10 symbols
10 * 2048 = 20480 complex samples
20480 * 4 = 81920 bytes
```

Inspector проверяет:

- sample count `20480/20480`;
- 10/10 ожидаемых символов;
- каждый символ относительно своего MATLAB golden;
- mean EVM;
- worst EVM;
- worst correlation;
- worst RMS phase error;
- всю 10-symbol waveform одной общей complex gain/phase нормировкой;
- тем самым — границы и переходы между всеми 9 соседними chirp.

Пример имени:

```text
hdl_sf7_bw125k_fs2000k_package.pcm
```

Важно: `package` здесь означает **текущий HDL package-stream contract**. Это пока не доказательство генерации полного стандартного LoRa PHY packet с Sync/SFD/PHDR/payload/FEC/CRC.

### Stage 3 — после ресемплера 24/25

Плановый sample rate:

```text
2.000 MS/s * 24/25 = 1.920 MS/s
```

Имя:

```text
hdl_sf7_bw125k_fs1920k_resampler.pcm
```

Inspector уже умеет:

- распознать Stage 3;
- проверить, что в metadata указано `Fs = 1.920 MS/s`;
- выполнить общий DSP-анализ записи;
- явно показать `NOT VERIFIED`, пока точные coefficients/phase convention production FIR-resampler не зафиксированы как golden reference.

После добавления production FIR/ресемплера в репозиторий golden-путь должен быть:

```text
MATLAB LoRa golden @ 2.000 MS/s
        ↓
reference FIR / resample 24/25
        ↓
expected waveform @ 1.920 MS/s
```

Тогда Stage 3 сможет проверять waveform/EVM и длину sample-to-sample.

### Stage 4 — после CIC x32

Плановый sample rate:

```text
1.920 MS/s * 32 = 61.440 MS/s
```

Имя:

```text
hdl_sf7_bw125k_fs61440k_cic.pcm
```

Сейчас Inspector распознаёт точку и проверяет metadata/sample rate, но возвращает `NOT VERIFIED`, потому что exact production CIC contract пока не представлен в репозитории как executable reference.

Для полноценного Stage 4 regression нужно зафиксировать:

- interpolation factor;
- число CIC stages;
- differential delay;
- gain/scaling;
- word lengths и truncation/rounding;
- ожидаемый droop;
- pipeline/latency convention.

### Stage 5 — после частотного переноса

Sample rate остаётся:

```text
Fs = 61.440 MS/s
```

Имя:

```text
hdl_sf7_bw125k_fs61440k_mixer.pcm
```

Stage 5 должен в итоге проверять:

- фактическую частоту переноса;
- ошибку center frequency;
- waveform после обратного переноса в baseband;
- EVM/correlation/phase относительно Stage 4 golden.

Пока точный NCO/mixer contract не зафиксирован в исходниках этого репозитория, Inspector показывает `NOT VERIFIED`.

## Выбор Stage в GUI

В Inspector появился список **TX checkpoint / Контрольная точка TX**:

```text
Auto from filename
1 — Chirp 2.000 MS/s
2 — Package 2.000 MS/s
3 — Resampler 1.920 MS/s
4 — CIC 61.440 MS/s
5 — Shift 61.440 MS/s
```

Рекомендуемый режим — `Auto from filename`. Ручной выбор нужен для диагностики и переопределяет только номер Stage; SF/BW/Fs по-прежнему берутся из имени HDL PCM.

## Формат CI16

Формат записи:

```text
signed int16, little-endian
I0, Q0, I1, Q1, I2, Q2, ...
```

Один complex sample занимает 4 байта:

```text
byte 0..1 : I0
byte 2..3 : Q0
byte 4..5 : I1
byte 6..7 : Q1
...
```

Внутреннее HDL-слово:

```text
31                         16 15                          0
+----------------------------+----------------------------+
|        I / real int16      |        Q / imag int16      |
+----------------------------+----------------------------+
```

Нынешний `ci16_file_io_pkg.vhd` записывает байты явно как:

```text
I_lo, I_hi, Q_lo, Q_hi
```

MATLAB loader читает:

```matlab
raw = fread(fid, Inf, "int16=>double", 0, "ieee-le");
iq = complex(raw(1:2:end), raw(2:2:end)) / 32768;
```

При Q14-подобной амплитуде HDL модуль сигнала в Inspector получается около `0.5` — это нормально.

## Уточнение по старому `output_hdl.pcm`

Ранее README слишком категорично утверждал, что старый testbench, записывавший packed `data_out` через VHDL `integer`, обязательно создавал неправильный CI16. Проверка самого бинарника показала, что **конкретная запись XSim фактически читается как корректный little-endian CI16 I/Q**: компоненты имеют ожидаемую амплитуду около 16383.

То есть проблема старого файла была **не доказана на уровне byte layout**.

Но этот blob всё равно нельзя использовать как golden current HDL:

```text
size = 90132 bytes
90132 / 4 = 22533 complex samples
22533 = 11 * 2048 + 5
```

Он не является одним SF7 chirp (`2048 samples`) и не соответствует нынешнему Stage 2 package (`20480 samples`). Кроме того, он получен старой версией chirp/phase logic, которую впоследствии исправили относительно MATLAB golden.

Поэтому вывод такой:

```text
old output_hdl.pcm:
CI16 byte representation — выглядит корректно
waveform / transaction history — устаревшие и не соответствуют current golden contract
```

Именно поэтому generated PCM не хранятся в Git: запись должна генерироваться из актуального testbench при каждой проверке.

## Как открыть запись

Из MATLAB:

```matlab
cd hdl/signal
open_in_inspector("../../build/ghdl-lora/hdl_sf7_bw125k_fs2000k_package.pcm")
```

Для русского интерфейса:

```matlab
open_in_inspector("../../build/ghdl-lora/hdl_sf7_bw125k_fs2000k_package.pcm", Language="ru")
```

После открытия нажать **Analyze / Анализ**.

## Автоматический Stage 1/2 regression

Workflow:

```text
.github/workflows/hdl-signal-ci.yml
```

проверяет путь:

```text
production VHDL
    ↓
GHDL + behavioral DDS/FIFO
    ↓
self-checking HDL golden test
    ↓
CI16 PCM
    ↓
MATLAB loader
    ↓
LoRa PHY Inspector / verification layer
    ↓
MATLAB golden
```

Stage 1 golden опирается на:

```text
model/matlab/+lora_phy/reference_chirp.m
model/matlab/+lora_phy/modulate_symbol.m
```

Stage 2 дополнительно проверяется функцией:

```text
model/matlab/+lora_phy/verify_tx_checkpoint.m
```

## Поддерживаемые имена

```text
Stage 1: hdl_sf<SF>_bw<BW>k_fs<FS>k_chirp-h<SYMBOL>-up.pcm
         hdl_sf<SF>_bw<BW>k_fs<FS>k_chirp-h<SYMBOL>-down.pcm

Stage 2: hdl_sf<SF>_bw<BW>k_fs<FS>k_package.pcm
Stage 3: hdl_sf<SF>_bw<BW>k_fs<FS>k_resampler.pcm
Stage 4: hdl_sf<SF>_bw<BW>k_fs<FS>k_cic.pcm
Stage 5: hdl_sf<SF>_bw<BW>k_fs<FS>k_mixer.pcm
```

Для текущего тракта ожидаются:

```text
Stage 1: Fs = 2000 kHz
Stage 2: Fs = 2000 kHz
Stage 3: Fs = 1920 kHz
Stage 4: Fs = 61440 kHz
Stage 5: Fs = 61440 kHz
```

## Практический checklist

- [ ] файл получен из актуального testbench;
- [ ] размер кратен 4 байтам;
- [ ] имя однозначно задаёт SF/BW/Fs/Stage;
- [ ] для Stage 1 указан `h` и `up/down`;
- [ ] Inspector показывает ожидаемую контрольную точку;
- [ ] sample rate совпадает с данной точкой тракта;
- [ ] Stage 1/2 дают `PASS` или объяснимый `WARN/FAIL`;
- [ ] Stage 3/4/5 не интерпретируются как `PASS`, пока нет production golden;
- [ ] при изменении HDL запущен CI.

## Связанные файлы

```text
hdl/srcs/formiration_chirp.vhd
hdl/srcs/phase_to_sample.vhd
hdl/srcs/formiration_package.vhd
hdl/tb/test_formiration_chirp_golden.vhd
hdl/tb/test_formiration_package_golden.vhd
hdl/tb/ci16_file_io_pkg.vhd
model/matlab/apps/lora_phy_inspector.m
model/matlab/+lora_phy/parse_hdl_recording_name.m
model/matlab/+lora_phy/verify_tx_checkpoint.m
model/matlab/+lora_phy/compare_iq_to_golden.m
model/matlab/+lora_phy/inspect_iq_capture.m
.github/workflows/hdl-signal-ci.yml
```
