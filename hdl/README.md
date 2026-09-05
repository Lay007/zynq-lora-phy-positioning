# HDL-генератор LoRa/CSS

Этот каталог содержит VHDL-реализацию формирования LoRa/CSS chirp и пакетного потока, Xilinx IP, тесты и вспомогательные средства для сравнения HDL с эталонной MATLAB-моделью.

На текущем этапе полностью верифицирован генератор отдельного CSS-символа (`formiration_chirp` + `phase_to_sample`). Блок `formiration_package` пока следует считать экспериментальным: его преамбула, FIFO-handshake и полный пакет ещё не покрыты такой же end-to-end golden-регрессией.

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
    └── open_in_inspector.m       # загрузка CI16 HDL-записи в MATLAB Inspector
```

HDL IQ-записи генерируются локально testbench и не обязаны храниться в Git. Расширение `*.pcm` игнорируется `.gitignore`.

## Текущая проверенная конфигурация

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

## Формат HDL IQ-записи: CI16

HDL testbench сохраняет обычный headerless complex-int16 поток, совместимый с распространённым представлением `CI16/SC16`:

```text
signed int16, little-endian
I0, Q0, I1, Q1, I2, Q2, ...
```

Каждый комплексный отсчёт занимает 4 байта:

```text
byte 0..1 : I0, signed int16 little-endian
byte 2..3 : Q0, signed int16 little-endian
byte 4..5 : I1
byte 6..7 : Q1
...
```

Логическая структура `data_out` внутри HDL остаётся:

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

Testbench **не пишет это 32-битное слово как VHDL `integer`**. Вместо этого он явно сохраняет байты в порядке:

```text
I_lo, I_hi, Q_lo, Q_hi
```

Поэтому файл можно читать обычным `int16`-reader без перестановки I/Q и без специального HDL-формата.

Выход `phase_to_sample` использует приблизительно Q14-амплитуду, поэтому типичный максимум LoRa-сигнала около `±16384`, то есть примерно половина полного диапазона signed int16. Это свойство численного масштаба HDL, а не отдельный файловый формат.

MATLAB Inspector нормирует CI16 по полному диапазону int16:

```matlab
raw = fread(fid, Inf, "int16=>double", 0, "ieee-le");
iq = complex(raw(1:2:end), raw(2:2:end)) / 32768;
```

Следовательно, HDL-сигнал с Q14-амплитудой будет иметь амплитуду около `0.5` в нормированном представлении Inspector.

### Требование к имени HDL-записи

Для новых HDL IQ-записей используется машинно-читаемое имя:

```text
hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
```

где:

- `<SF>` — spreading factor;
- `<BW_KHZ>` — bandwidth в кГц;
- `<FS_KHZ>` — частота дискретизации в кГц;
- `<TAG>` — короткое назначение записи латиницей, цифрами и `-`.

Примеры:

```text
hdl_sf7_bw125k_fs2000k_package.pcm
hdl_sf7_bw125k_fs2000k_chirp-h17-up.pcm
hdl_sf7_bw125k_fs2000k_chirp-h64-down.pcm
```

Не следует использовать имена `output.pcm`, `signal.pcm` или `test.pcm`: raw CI16 не содержит метаданных, и без имени невозможно надёжно восстановить SF/BW/Fs.

`test_formiration_package.vhd` формирует:

```text
hdl_sf7_bw125k_fs2000k_package.pcm
```

### Открытие записи в LoRa PHY Inspector

Рядом с каталогом записей находится helper:

```text
hdl/signal/open_in_inspector.m
```

Он:

1. проверяет имя файла;
2. извлекает SF, BW и Fs из имени;
3. выбирает формат `ci16`;
4. открывает LoRa PHY Inspector;
5. выставляет частоту дискретизации из имени;
6. выбирает MATLAB golden reference по тегу файла;
7. после **Analyze** запускает EVM/correlation/phase-error проверку.

Пример:

```matlab
cd hdl/signal
open_in_inspector("hdl_sf7_bw125k_fs2000k_package.pcm")
```

Если в `hdl/signal` находится ровно одна запись по принятому шаблону, можно вызвать:

```matlab
open_in_inspector
```

Для `package` в качестве golden reference используется первый preamble `h=0` upchirp. Для имён `chirp-h17-up` / `chirp-h64-down` номер символа и направление берутся из `<TAG>`.

Inspector ищет лучший сдвиг границы в небольшом окне и выводит Golden EVM, normalized correlation, RMS/max phase error, peak sample error и итог `PASS/WARN`. Текущие цифровые regression-пороги: EVM `<= 1 %`, correlation `>= 0.999`, RMS phase error `<= 1°`.

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

Первый sample должен соответствовать фазе `n = 0` эталонной модели, а не фазе после первого интегрирования частоты.

## Golden-регрессия

Автоматическая проверка находится в workflow:

```text
.github/workflows/hdl-signal-ci.yml
```

Для CI используется GHDL. Закрытая simulation-модель Xilinx DDS в GitHub runner недоступна, поэтому в симуляции только IP DDS заменяется на поведенческую модель:

```text
hdl/tb/dds_sin_cos_only_stub.vhd
```

При этом проверяются production-файлы:

```text
hdl/srcs/phase_to_sample.vhd
hdl/srcs/formiration_chirp.vhd
```

Дополнительно CI разбирает `dds_sin_cos_only.xci` и проверяет критичные параметры интерфейса DDS: внешний phase input, ширину фазы 16 бит, ширину sin/cos 16 бит и 32-битный комплексный выход.

### Проверяемые символы

Upchirp:

```text
h = 0, 1, 17, 63, 127
```

Downchirp:

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

При сравнении исходной HDL с MATLAB/C++ golden-моделью были исправлены:

- лишний 2049-й отсчёт;
- преждевременное обновление фазового аккумулятора перед первым sample;
- порядок компонент DDS относительно `{real, imag}`;
- начальная фаза и фазовое приращение для точного соответствия MATLAB SF7/L16;
- формат сохраняемой симуляционной IQ-записи: вместо packed VHDL `integer` используется обычный CI16 `I,Q,I,Q,...`.

## Тактирование и частота дискретизации

Важно различать **частоту тактирования логики** и **частоту дискретизации формируемого сигнала**.

В Xilinx IP сейчас указан `ACLK = 100 MHz`, но проверенная математическая конфигурация chirp предполагает:

```text
Fs = 2 MHz.
```

Следовательно, в реальном FPGA-тракте должно быть явно обеспечено, что новый I/Q sample принимается передающим трактом с эффективной скоростью **2 Мвыб/с**. Это может быть реализовано через clock enable, rate adapter, интерполяцию/decimation или соответствующий интерфейс следующего блока.

Сам факт работы DDS на 100 МГц не означает, что RF/baseband sample rate автоматически равен 2 МГц. До аппаратной приёмки необходимо проследить этот контракт до входа DAC/AD936x-тракта.

## Текущие ограничения

Подтверждено:

- SF7;
- BW 125 кГц;
- L=16;
- upchirp/downchirp;
- информационные CSS-символы через `h_in`;
- длина символа 2048 отсчётов;
- соответствие дискретной фазе MATLAB-модели;
- корректный порядок I/Q;
- компиляция production VHDL в GHDL;
- параметры интерфейса Xilinx DDS из `.xci`;
- стандартный файловый порядок CI16 для симуляционной записи.

Пока **не подтверждено**:

- другие SF/BW/L;
- bit-exact симуляция самого Xilinx DDS Compiler в Vivado;
- полный `formiration_package` против MATLAB packet waveform;
- packet preamble/SFD/header/payload как единый LoRa TX waveform;
- корректность FIFO-handshake под backpressure;
- реальный аппаратный sample-rate contract 100 МГц → 2 Мвыб/с;
- передача сформированного HDL-сигнала через AD936x и сравнение с эфирной записью.

## Следующие шаги

1. добавить self-checking regression для `formiration_package`;
2. сравнить полную последовательность `preamble -> symbols` с MATLAB packet waveform;
3. проверить FIFO backpressure и границы соседних символов;
4. формально зафиксировать преобразование `100 MHz fabric clock -> 2 MS/s sample stream`;
5. запустить Vivado/XSim regression с настоящим DDS Compiler IP;
6. провести аппаратный loopback/SDR capture и сравнить IQ с MATLAB/C++/HDL эталонами;
7. затем расширять матрицу параметров SF/BW/L.

## Запуск HDL regression локально

На Linux с установленным GHDL:

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

При успехе:

```text
HDL LoRa chirp golden regression PASS
```
