# HDL-генератор LoRa/CSS

Этот каталог содержит VHDL-реализацию формирования LoRa/CSS chirp и пакетного потока, а также Xilinx IP и самопроверяющиеся тесты для сравнения HDL с эталонной MATLAB-моделью.

На текущем этапе полностью верифицирован именно генератор отдельного CSS-символа (`formiration_chirp` + `phase_to_sample`). Блок `formiration_package` пока следует считать экспериментальным: его преамбула, FIFO-handshake и полный пакет ещё не покрыты такой же end-to-end golden-регрессией.

## Структура

```text
hdl/
├── ip/
│   ├── dds_sin_cos_only.xci      # Xilinx DDS Compiler: phase -> sin/cos
│   └── fifo_1024_32.xci          # AXI-Stream FIFO пакетного генератора
├── srcs/
│   ├── formiration_chirp.vhd     # формирование одного CSS chirp/символа
│   ├── phase_to_sample.vhd       # накопитель фазы и преобразование в I/Q
│   └── formiration_package.vhd   # очередь символов и формирование преамбулы
├── tb/
│   ├── dds_sin_cos_only_stub.vhd
│   ├── test_formiration_chirp_golden.vhd
│   └── test_formiration_package.vhd
└── signal/
    ├── output_hdl.pcm            # исторический результат ручной симуляции
    └── open_in_inspector.m       # загрузка HDL PCM в MATLAB LoRa PHY Inspector
```

## Текущая проверенная конфигурация

HDL chirp generator сейчас целенаправленно проверен для первой аппаратной конфигурации проекта:

| Параметр | Значение |
|---|---:|
| Spreading Factor | SF7 |
| Число chips в символе | 128 |
| Bandwidth | 125 кГц |
| Samples per chip, `L` | 16 |
| Частота дискретизации сигнала | 2 Мвыб/с |
| Отсчётов на символ | 2048 |
| Фазовый аккумулятор DDS | 16 бит |
| I/Q | signed 16 bit |

Связь параметров:

```text
Fs = BW * L = 125 кГц * 16 = 2 МГц
Ns = 2^SF * L = 128 * 16 = 2048 отсчётов
```

Поддержка других SF/BW в интерфейсе предусмотрена полями `sf_in` и `bw_in`, но текущая production-логика содержит настроенную ветку именно для SF7/BW125. Другие комбинации нельзя считать проверенными, пока для них не появятся параметры и golden-тесты.

## Формат HDL IQ-записи (`hdl32`)

Файлы `.pcm`, сформированные HDL testbench, **не являются WAV-файлами и не являются обычным stereo PCM с чередованием `I,Q,I,Q,...`**. Каждый комплексный отсчёт сохраняется одним 32-битным little-endian словом.

Логическая структура `data_out` в HDL:

```text
31                         16 15                          0
+----------------------------+----------------------------+
|        I / real int16      |        Q / imag int16      |
+----------------------------+----------------------------+
```

То есть:

```text
data_out[31:16] = I = real = cosine, signed int16
data_out[15:0]  = Q = imag = sine,   signed int16
```

Амплитуда после `phase_to_sample` имеет приблизительно Q14-масштаб:

```text
1.0 ~= 16384
-1.0 ~= -16384
```

Testbench `test_formiration_package.vhd` записывает весь `data_out` как 32-битный `integer`. На little-endian машине младшие байты слова оказываются в файле первыми. Поэтому если ошибочно открыть такой файл просто как поток `int16`, компоненты будут видны в порядке:

```text
Q0, I0, Q1, I1, Q2, I2, ...
```

Это **не означает, что I и Q перепутаны внутри HDL**. В интерфейсе HDL порядок правильный: `{I,Q}`. Перестановка появляется только при неверной интерпретации 32-битного packed-word файла как обычного массива `int16`.

MATLAB-загрузчик проекта читает такой файл как формат `hdl32`: сначала загружает каждое 32-битное little-endian слово, затем явно извлекает старшие 16 бит как I и младшие 16 бит как Q и нормирует компоненты на 16384.

```matlab
[iq, info] = lora_phy.load_iq_capture("record.pcm", "hdl32");
```

Для расширения `.pcm` режим `auto` также выбирает `hdl32`.

### Требование к имени HDL-записи

Для новых HDL IQ-записей используется машинно-читаемое имя:

```text
hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
```

где:

- `<SF>` — spreading factor без префикса `SF` внутри значения;
- `<BW_KHZ>` — bandwidth в кГц;
- `<FS_KHZ>` — частота дискретизации в кГц;
- `<TAG>` — короткое назначение записи латиницей, цифрами и `-`.

Примеры:

```text
hdl_sf7_bw125k_fs2000k_package.pcm
hdl_sf7_bw125k_fs2000k_chirp-h17-up.pcm
hdl_sf7_bw125k_fs2000k_chirp-h64-down.pcm
```

Не рекомендуется использовать безымянные варианты вроде `output.pcm`, `signal.pcm` или `test.pcm`, потому что raw PCM не содержит метаданных и через некоторое время невозможно однозначно восстановить SF/BW/Fs.

Текущий файл:

```text
hdl/signal/output_hdl.pcm
```

сохранён как **legacy-артефакт** и появился до введения соглашения об именах. Новые записи должны соответствовать шаблону выше.

### Открытие записи в LoRa PHY Inspector

Рядом с записью находится helper:

```text
hdl/signal/open_in_inspector.m
```

Для файла с новым стандартным именем скрипт автоматически извлекает SF, BW и Fs из имени, устанавливает формат `hdl32`, открывает LoRa PHY Inspector и запускает анализ.

Из MATLAB:

```matlab
cd hdl/signal
open_in_inspector("hdl_sf7_bw125k_fs2000k_package.pcm")
```

Если аргумент не указан, helper ищет единственную запись, соответствующую новому шаблону. Пока в каталоге находится только исторический `output_hdl.pcm`, он используется как legacy-fallback с параметрами SF7/BW125/Fs=2 МГц.

## Соответствие MATLAB-модели

Авторитетная floating-point модель находится в:

```text
model/matlab/+lora_phy/reference_chirp.m
model/matlab/+lora_phy/modulate_symbol.m
```

Для одного reference upchirp MATLAB использует фазу

```text
phaseCycles[n] = 0.5*n^2/(N*L^2) - 0.5*n/L,
```

где:

```text
N = 2^SF,
n = 0 ... N*L-1.
```

Комплексный отсчёт:

```text
x[n] = exp(j*2*pi*phaseCycles[n]).
```

Downchirp является комплексно-сопряжённым upchirp.

Информационный символ `h` в MATLAB задаётся циклическим сдвигом:

```matlab
circshift(reference_chirp, -h*samplesPerChip)
```

HDL реализует тот же закон через начальную фазу и линейно меняющееся фазовое приращение DDS. Для SF7/L16 дискретное приращение фазы в 16-битном фазовом формате соответствует точной разности соседних значений квадратичной фазы MATLAB-модели.

## Интерфейс `formiration_chirp`

Основные входы:

- `valid_in` — запрос на запуск нового символа;
- `h_in` — номер CSS/LoRa-символа;
- `sf_in` — код spreading factor;
- `bw_in` — код bandwidth;
- `direction_in` — направление chirp;
- `ready_out` — блок готов принять следующий символ.

Выходы:

- `valid_out` — текущий `data_out` содержит валидный I/Q-отсчёт;
- `data_out[31:16]` — signed real/I;
- `data_out[15:0]` — signed imag/Q.

Для одного принятого SF7/L16 символа генератор обязан выдать ровно **2048** валидных комплексных отсчётов.

## Фазовый тракт

`formiration_chirp.vhd` формирует последовательность фазовых приращений, а `phase_to_sample.vhd`:

1. загружает начальную фазу нового символа;
2. выдаёт текущую фазу в DDS;
3. после выдачи отсчёта обновляет фазовый аккумулятор;
4. приводит выход Xilinx DDS к принятому в проекте формату `{real, imag}`.

Такой порядок важен: первый sample должен соответствовать фазе `n = 0` эталонной модели, а не фазе после первого интегрирования частоты.

## Golden-регрессия

Автоматическая проверка находится в workflow:

```text
.github/workflows/hdl-signal-ci.yml
```

Для CI используется GHDL. Закрытая simulation-модель Xilinx DDS в GitHub runner недоступна, поэтому в симуляции только IP DDS заменяется на поведенческую модель:

```text
hdl/tb/dds_sin_cos_only_stub.vhd
```

Она имеет тот же 16-битный phase interface и формирует 16-битные sine/cosine. При этом проверяются настоящие production-файлы:

```text
hdl/srcs/phase_to_sample.vhd
hdl/srcs/formiration_chirp.vhd
```

Дополнительно CI разбирает `dds_sin_cos_only.xci` и проверяет критичные параметры интерфейса DDS: внешний phase input, ширину фазы 16 бит, ширину sin/cos 16 бит и 32-битный комплексный выход.

### Проверяемые символы

Для upchirp regression проверяются:

```text
h = 0, 1, 17, 63, 127
```

Для downchirp:

```text
h = 0, 64
```

Для каждого случая testbench:

1. запускает production HDL;
2. принимает ровно 2048 валидных отсчётов;
3. вычисляет ожидаемую фазу по MATLAB-формуле;
4. сравнивает I и Q sample-by-sample;
5. проверяет отсутствие 2049-го отсчёта.

Успешная проверка заканчивается сообщением:

```text
HDL LoRa chirp golden regression PASS
```

Таким образом, для **SF7 / BW125 / L16** корректность формирования отдельного CSS/LoRa-символа подтверждается автоматической HDL-регрессией.

## Что было исправлено при верификации

Первоначальная версия HDL была близка к требуемой математике, но при сравнении с MATLAB/C++ golden-моделью обнаружились принципиальные расхождения:

- граница счётчика позволяла сформировать лишний, 2049-й, отсчёт;
- первый отсчёт получался после преждевременного обновления фазового аккумулятора;
- порядок компонент DDS не был приведён к принятому в репозитории формату `{real, imag}`;
- начальная фаза и фазовое приращение были уточнены так, чтобы воспроизводить дискретную MATLAB-модель для SF7/L16.

После исправлений self-checking GHDL regression проходит полностью.

## Тактирование и частота дискретизации

Важно различать **частоту тактирования логики** и **частоту дискретизации формируемого сигнала**.

В Xilinx IP сейчас указан `ACLK = 100 MHz`, но проверенная математическая конфигурация chirp предполагает:

```text
Fs = 2 MHz.
```

Следовательно, в реальном FPGA-тракте должно быть явно обеспечено, что новый I/Q sample принимается передающим трактом с эффективной скоростью **2 Мвыб/с**. Это может быть реализовано через clock enable, rate adapter, интерполяцию/decimation или соответствующий интерфейс следующего блока.

Сам факт работы DDS на 100 МГц не означает, что RF/baseband sample rate автоматически равен 2 МГц. До аппаратной приёмки необходимо проследить этот контракт до входа DAC/AD936x-тракта.

## Текущие ограничения

На данный момент подтверждено:

- SF7;
- BW 125 кГц;
- L=16;
- upchirp/downchirp;
- информационные CSS-символы через `h_in`;
- длина символа 2048 отсчётов;
- соответствие дискретной фазе MATLAB-модели;
- корректный порядок I/Q;
- компиляция production VHDL в GHDL;
- параметры интерфейса Xilinx DDS из `.xci`.

Пока **не подтверждено**:

- другие SF/BW/L;
- bit-exact симуляция самого Xilinx DDS Compiler в Vivado;
- полный `formiration_package` против MATLAB packet waveform;
- packet preamble/SFD/header/payload как единый LoRa TX waveform;
- корректность FIFO-handshake под backpressure;
- реальный аппаратный sample-rate contract 100 МГц → 2 Мвыб/с;
- передача сформированного HDL-сигнала через AD936x и сравнение с эфирной записью.

## Следующие шаги

Рекомендуемый порядок дальнейшей верификации:

1. добавить self-checking regression для `formiration_package`;
2. сравнить полную последовательность `preamble -> symbols` с MATLAB packet waveform;
3. проверить FIFO backpressure и границы соседних символов;
4. формально зафиксировать преобразование `100 MHz fabric clock -> 2 MS/s sample stream`;
5. запустить Vivado/XSim regression с настоящим DDS Compiler IP;
6. провести аппаратный loopback/SDR capture и сравнить IQ с MATLAB/C++/HDL эталонами;
7. затем расширять матрицу параметров SF/BW/L.

## Запуск HDL regression локально

На Linux с установленным GHDL команды эквивалентны GitHub Actions:

```bash
mkdir -p build/ghdl-lora

ghdl -a --std=08 --workdir=build/ghdl-lora hdl/tb/dds_sin_cos_only_stub.vhd
ghdl -a --std=08 --workdir=build/ghdl-lora hdl/srcs/phase_to_sample.vhd
ghdl -a --std=08 --workdir=build/ghdl-lora hdl/srcs/formiration_chirp.vhd
ghdl -a --std=08 --workdir=build/ghdl-lora hdl/tb/test_formiration_chirp_golden.vhd
ghdl -e --std=08 --workdir=build/ghdl-lora test_formiration_chirp_golden
ghdl -r --std=08 --workdir=build/ghdl-lora test_formiration_chirp_golden \
  --assert-level=error --stop-time=5ms
```

При успехе должно появиться:

```text
HDL LoRa chirp golden regression PASS
```
