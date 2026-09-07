# HDL IQ-записи для LoRa PHY Inspector

Каталог `hdl/signal` предназначен для работы с IQ-записями, сформированными HDL-моделью LoRa/CSS и открываемыми в MATLAB-приложении **LoRa PHY Inspector**.

Важно: бинарные `*.pcm` здесь считаются **генерируемыми артефактами**, а не исходными файлами проекта. Они не должны храниться в Git. Актуальные записи формируются testbench-ами и, при запуске CI, публикуются как GitHub Actions artifacts вместе с отчётом Inspector.

## Что находится в каталоге

```text
hdl/signal/
├── README.md
└── open_in_inspector.m
```

`open_in_inspector.m` — вспомогательный MATLAB-скрипт, который:

1. находит или принимает путь к HDL IQ-записи;
2. разбирает SF, BW и Fs из имени файла;
3. выбирает формат `CI16`;
4. открывает LoRa PHY Inspector;
5. выставляет частоту дискретизации;
6. выбирает MATLAB golden reference;
7. позволяет выполнить DSP-анализ и golden-сравнение кнопкой **Analyze**.

## Формат файла

Для HDL-записей используется raw complex int16 без заголовка:

```text
signed int16, little-endian
I0, Q0, I1, Q1, I2, Q2, ...
```

Один комплексный отсчёт занимает 4 байта:

```text
byte 0..1 : I0, signed int16 little-endian
byte 2..3 : Q0, signed int16 little-endian
byte 4..5 : I1
byte 6..7 : Q1
...
```

Внутри HDL `data_out` имеет вид:

```text
31                         16 15                          0
+----------------------------+----------------------------+
|        I / real int16      |        Q / imag int16      |
+----------------------------+----------------------------+
```

То есть:

```text
data_out[31:16] = I = real = cos
data_out[15:0]  = Q = imag = sin
```

При записи в файл байты должны быть явно разложены как:

```text
I_lo, I_hi, Q_lo, Q_hi
```

Нельзя просто записывать весь `std_logic_vector(31 downto 0)` как VHDL `integer`: такой файл не является корректным CI16-потоком для Inspector.

## Нормирование в Inspector

MATLAB loader читает CI16 как signed int16 little-endian и нормирует по полному диапазону `int16`:

```matlab
raw = fread(fid, Inf, "int16=>double", 0, "ieee-le");
iq = complex(raw(1:2:end), raw(2:2:end)) / 32768;
```

Текущий HDL-тракт формирует амплитуду примерно Q14, то есть типичные значения находятся около `±16384`. Поэтому в Inspector модуль идеального сигнала будет около `0.5`, а не около `1.0`.

Это ожидаемое поведение и не является потерей амплитуды при загрузке.

## Обязательное имя файла

Файл должен называться:

```text
hdl_sf<SF>_bw<BW_KHZ>k_fs<FS_KHZ>k_<TAG>.pcm
```

Примеры корректных имён:

```text
hdl_sf7_bw125k_fs2000k_package.pcm
hdl_sf7_bw125k_fs2000k_chirp-h0-up.pcm
hdl_sf7_bw125k_fs2000k_chirp-h17-up.pcm
hdl_sf7_bw125k_fs2000k_chirp-h64-down.pcm
```

### Поддерживаемые теги

Для автоматической golden-верификации сейчас допустимы два типа `<TAG>`:

```text
package
chirp-h<SYMBOL>-up
chirp-h<SYMBOL>-down
```

Для SF7 номер символа должен быть в диапазоне:

```text
0 ... 127
```

Имя вида:

```text
hdl_sf7_bw125k_fs2000k_chirp.pcm
```

считается **неоднозначным и запрещено**, потому что по нему невозможно определить номер символа и направление chirp. Inspector не должен молча предполагать `h=0 up` для неизвестного файла.

Также не следует использовать имена:

```text
output.pcm
signal.pcm
test.pcm
```

Raw PCM не содержит SF/BW/Fs внутри файла, поэтому метаданные должны однозначно кодироваться в имени.

## Проверенная конфигурация

Текущая полноценно проверенная HDL-конфигурация:

| Параметр | Значение |
|---|---:|
| Spreading Factor | SF7 |
| Bandwidth | 125 кГц |
| Samples per chip `L` | 16 |
| Sample rate | 2 Мвыб/с |
| Chips per symbol | 128 |
| Samples per symbol | 2048 |
| I/Q | signed int16 |
| File format | CI16 little-endian |

Связь параметров:

```text
Fs = BW × L
   = 125 kHz × 16
   = 2 MHz

Ns = 2^SF × L
   = 128 × 16
   = 2048 complex samples/symbol
```

Для одного отдельного SF7/BW125/L16 chirp корректный CI16-файл должен иметь:

```text
2048 complex samples × 4 bytes = 8192 bytes
```

Текущий package regression формирует 10 символов:

```text
10 × 2048 = 20480 complex samples
20480 × 4 = 81920 bytes
```

Если размер файла существенно отличается от ожидаемого количества символов, это повод проверить testbench, `valid_out`, условия остановки записи и сам способ сериализации I/Q.

## Как получить корректный PCM

Предпочтительный источник записи — self-checking testbench:

```text
hdl/tb/test_formiration_package_golden.vhd
```

Он проверяет каждый сформированный I/Q sample относительно golden-модели и одновременно записывает уже проверенный поток в:

```text
build/ghdl-lora/hdl_sf7_bw125k_fs2000k_package.pcm
```

В CI для этой записи дополнительно проверяется точный размер:

```text
81920 bytes
```

Для ручной симуляции также существует:

```text
hdl/tb/test_formiration_package.vhd
```

Он использует общий writer `ci16_file_io_pkg.vhd` и завершает запись после ожидаемого числа валидных комплексных отсчётов.

## Как открыть запись в Inspector

Из MATLAB:

```matlab
cd hdl/signal
open_in_inspector("../../build/ghdl-lora/hdl_sf7_bw125k_fs2000k_package.pcm")
```

Можно передать и абсолютный путь:

```matlab
open_in_inspector("D:\work\zynq-lora-phy-positioning\build\ghdl-lora\hdl_sf7_bw125k_fs2000k_package.pcm")
```

Если в `hdl/signal` локально находится ровно один файл, соответствующий принятому шаблону, допустим вызов:

```matlab
open_in_inspector
```

После открытия нажать **Analyze**.

## Что проверяет Inspector

Для HDL CI16-записи Inspector выполняет два уровня анализа.

### 1. DSP-анализ записи

Определяются:

- границы активного участка;
- occupied bandwidth;
- наиболее вероятный LoRa bandwidth;
- spreading factor;
- symbol duration;
- carrier offset;
- residual CFO;
- относительный SNR;
- DC offset;
- I/Q power imbalance;
- clipping;
- dechirped FFT bins.

Это диагностический PHY-анализ, а не полный декодер стандартного LoRa packet.

### 2. Golden-сравнение

Для корректно именованного HDL-файла Inspector вызывает MATLAB golden comparison.

Для:

```text
..._package.pcm
```

сравнивается первый `h=0 upchirp`.

Для:

```text
..._chirp-h17-up.pcm
```

golden reference будет `h=17 upchirp`.

Для:

```text
..._chirp-h64-down.pcm
```

golden reference будет `h=64 downchirp`.

Проверяются:

- EVM;
- normalized correlation;
- RMS phase error;
- max phase error;
- peak normalized sample error;
- complex gain/phase;
- sample alignment.

Текущие regression-пороги:

```text
EVM <= 1 %
correlation >= 0.999
RMS phase error <= 1 degree
```

## Автоматическая end-to-end проверка

Workflow:

```text
.github/workflows/hdl-signal-ci.yml
```

проверяет цепочку:

```text
production VHDL
      ↓
GHDL
      ↓
behavioral DDS/FIFO models
      ↓
self-checking golden testbench
      ↓
CI16 file writer
      ↓
*.pcm
      ↓
MATLAB loader
      ↓
LoRa PHY Inspector DSP
      ↓
MATLAB golden comparison
```

Для текущего package regression ожидается:

```text
20480 complex CI16 samples
SF7
BW 125 kHz
carrier near DC
golden PASS
```

Таким образом проверяется не только математическая формула chirp, но и реальный путь представления результата HDL как бинарной IQ-записи, которую затем читает Inspector.

## Почему `*.pcm` не хранятся в Git

В корневом `.gitignore` есть правило:

```text
*.pcm
```

Это сделано намеренно.

PCM-файлы являются результатом симуляции и могут быть воспроизведены из исходного VHDL и testbench. Хранение таких файлов в Git создаёт несколько рисков:

- можно случайно закоммитить устаревшую запись;
- имя файла может не соответствовать фактическому содержимому;
- старый бинарный blob может выглядеть как новый результат после простого переименования;
- невозможно code review-ить бинарный diff;
- репозиторий быстро разрастается;
- CI может проверять freshly-generated сигнал, а пользователь — случайно открыть другой закоммиченный файл.

Поэтому source of truth — это:

```text
HDL source + self-checking testbench + golden model
```

а PCM — только временный reproducible artifact.

HDL workflow содержит отдельную защиту: если в `hdl/signal` будет принудительно закоммичен `*.pcm`, CI должен завершиться ошибкой.

## История с устаревшим `output_hdl.pcm`

Ранее в репозитории существовал файл:

```text
hdl/signal/output_hdl.pcm
```

Он был создан старым testbench, который записывал packed 32-bit `data_out` через преобразование к VHDL `integer`. Такая запись не соответствовала принятому впоследствии CI16-контракту.

Файл был удалён как устаревший.

Позже тот же бинарный Git blob был случайно возвращён под именем:

```text
hdl_sf7_bw125k_fs2000k_chirp.pcm
```

Это было обнаружено по совпадающему Git blob SHA и по размеру файла:

```text
90132 bytes
90132 / 4 = 22533 complex samples
22533 = 11 × 2048 + 5
```

То есть файл не соответствовал ни одному SF7 chirp, ни текущему 10-symbol package regression.

Inspector в этом случае правильно показывал ошибку: проблема была в самом входном файле, а не в текущей HDL-модели или MATLAB Inspector.

После этого введены дополнительные ограничения:

1. generated `*.pcm` не должны коммититься;
2. CI проверяет отсутствие tracked PCM в `hdl/signal`;
3. имя `..._chirp.pcm` запрещено как неоднозначное;
4. одиночный chirp обязан кодировать symbol и direction в имени;
5. CI генерирует собственный fresh PCM и проверяет именно его end-to-end.

## Что считается доказанным сейчас

Для **SF7 / BW125 / L16 / Fs=2 MHz** подтверждено:

- все `h=0...127` для upchirp;
- все `h=0...127` для downchirp;
- ровно 2048 samples на символ;
- отсутствие 2049-го sample;
- I/Q ordering;
- CI16 little-endian byte layout;
- текущий 10-symbol `formiration_package` waveform;
- загрузка сформированного CI16 в MATLAB;
- определение Inspector-ом SF7/BW125;
- golden EVM/correlation/phase verification.

## Что пока не следует считать доказанным

Текущие regression-тесты **не доказывают**:

- полное соответствие стандартному LoRa packet framing;
- SFD/header/payload coding/interleaving/FEC всей стандартной PHY-цепочки;
- все SF/BW/Fs комбинации;
- bit-exact поведение proprietary Xilinx DDS Compiler в Vivado/XSim;
- timing closure;
- соответствие target FPGA по ресурсам;
- реальный sample-rate contract 100 MHz fabric → 2 MS/s IQ на аппаратуре;
- передачу через AD936x;
- RF/OTA качество сформированного HDL-сигнала.

Для этого нужны следующие ступени верификации:

```text
MATLAB golden
    ↓
GHDL regression
    ↓
Vivado/XSim с реальным Xilinx DDS/FIFO
    ↓
synthesis / implementation / STA
    ↓
Zynq + AD936x
    ↓
RF/cable/OTA capture
    ↓
LoRa PHY Inspector
```

## Практический чек-лист при появлении новой HDL записи

Перед анализом нового PCM полезно проверить:

- [ ] имя соответствует `hdl_sf..._bw..._fs..._<TAG>.pcm`;
- [ ] tag равен `package` или `chirp-h<SYMBOL>-up/down`;
- [ ] размер файла кратен 4 байтам;
- [ ] число complex samples соответствует ожидаемой длительности;
- [ ] I/Q записаны как `int16 little-endian`;
- [ ] порядок — `I,Q,I,Q,...`;
- [ ] файл получен из актуального testbench;
- [ ] нет старого/переименованного binary artifact;
- [ ] Inspector использует Fs из имени файла;
- [ ] golden verification даёт ожидаемый результат;
- [ ] при изменениях HDL пройден `HDL LoRa Signal CI`.

## Связанные файлы

HDL:

```text
hdl/srcs/formiration_chirp.vhd
hdl/srcs/phase_to_sample.vhd
hdl/srcs/formiration_package.vhd
```

Testbench и CI16 writer:

```text
hdl/tb/test_formiration_chirp_golden.vhd
hdl/tb/test_formiration_package_golden.vhd
hdl/tb/test_formiration_package.vhd
hdl/tb/ci16_file_io_pkg.vhd
```

MATLAB Inspector:

```text
model/matlab/apps/lora_phy_inspector.m
model/matlab/+lora_phy/load_iq_capture.m
model/matlab/+lora_phy/parse_hdl_recording_name.m
model/matlab/+lora_phy/inspect_iq_capture.m
model/matlab/+lora_phy/compare_iq_to_golden.m
model/matlab/run_hdl_inspector_regression.m
```

CI:

```text
.github/workflows/hdl-signal-ci.yml
```

Общее описание HDL-части проекта:

```text
hdl/README.md
```
