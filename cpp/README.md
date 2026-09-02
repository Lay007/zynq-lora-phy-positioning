# C++ модель CSS chirp

Каталог `cpp/` содержит переносимую C++20-реализацию опорного CSS chirp,
отдельный DDS/frequency-shift блок, демонстрационную программу и regression
тесты. C++ модель предназначена для промежуточного уровня проверки между
MATLAB floating-point моделью и HDL/FPGA реализацией.

Рекомендуемая цепочка верификации:

```text
MATLAB floating point
        ↓
C++ fixed-point-like model (Q13)
        ↓
FPGA golden ROM (Q10)
        ↓
HDL / FPGA
```

Visual Studio solution сохранён для удобной работы в Windows, а
`CMakeLists.txt` является основным воспроизводимым способом сборки и
используется в GitHub Actions. Для повседневной работы рекомендуется использовать
`CMakePresets.json`: он задаёт одинаковые имена конфигураций для Linux,
Windows, Visual Studio и командной строки.

## Содержимое каталога

```text
cpp/
├── CMakeLists.txt              CMake-сборка
├── CMakePresets.json           готовые Debug/Release preset'ы
├── README.md                   этот документ
├── LoRa.slnx                   Visual Studio solution
├── LoRa/
│   ├── LoRa.cpp                демонстрационная программа
│   ├── chirp_modulator.*       генератор CSS chirp
│   ├── frequency_shift.*       DDS / frequency shift
│   ├── cplx.h                  простой комплексный fixed-point тип
│   ├── reader_file.h           чтение бинарных данных
│   └── writer_file.h           запись бинарных данных
└── tests/
    └── test_chirp.cpp          regression-тест C++ ↔ golden ROM
```

## Требования

Минимальные требования:

- CMake 3.20 или новее;
- компилятор с поддержкой C++20;
- Windows, Linux или другая платформа с подходящим C++ toolchain.

Проверяемые в CI конфигурации:

- Ubuntu + GCC;
- Windows + MSVC.

Для самой C++ модели MATLAB, Vivado и дополнительные библиотеки не нужны.
Golden regression использует уже сохранённый в репозитории файл FPGA ROM.

## Быстрый старт через CMake Presets

`CMakePresets.json` находится рядом с `CMakeLists.txt`, поэтому команды preset
запускаются из каталога `cpp/`.

Release:

```bash
cd cpp
cmake --preset release
cmake --build --preset release
ctest --preset release
```

Debug:

```bash
cd cpp
cmake --preset debug
cmake --build --preset debug
ctest --preset debug
```

Preset автоматически включает `BUILD_TESTING=ON` и создаёт отдельные каталоги
сборки:

```text
build/cpp-release/
build/cpp-debug/
```

Имена `release` и `debug` одинаковы для трёх стадий:

```text
cmake --preset <имя>          configure
cmake --build --preset <имя>  build
ctest --preset <имя>          tests
```

Это рекомендуемый способ локальной сборки: он уменьшает число ручных параметров
и делает команды одинаковыми на разных рабочих местах.

Посмотреть доступные preset'ы можно так:

```bash
cd cpp
cmake --list-presets=all
```

## Сборка без preset'ов

При необходимости остаётся доступна обычная CMake-команда из корня репозитория:

```bash
cmake -S cpp -B build/cpp -DCMAKE_BUILD_TYPE=Release
cmake --build build/cpp --config Release --parallel
ctest --test-dir build/cpp -C Release --output-on-failure
```

После сборки создаются основные цели:

- `lora_cpp_core` — библиотека с алгоритмами;
- `lora_chirp_demo` — демонстрационная программа;
- `lora_cpp_tests` — regression-тесты, если включён `BUILD_TESTING`.

`BUILD_TESTING` включён CMake/CTest по умолчанию. Чтобы собрать только библиотеку
и demo без тестов:

```bash
cmake -S cpp -B build/cpp -DBUILD_TESTING=OFF
cmake --build build/cpp --parallel
```

## Linux

Пример для Ubuntu/Debian:

```bash
sudo apt update
sudo apt install -y build-essential cmake

git clone https://github.com/Lay007/zynq-lora-phy-positioning.git
cd zynq-lora-phy-positioning
git checkout lora_cpp

cd cpp
cmake --preset release
cmake --build --preset release
ctest --preset release
```

Для GCC/Clang библиотека и тесты компилируются с:

```text
-Wall -Wextra -Wpedantic -Werror
```

То есть предупреждения компилятора в переносимом C++ коде рассматриваются как
ошибки.

## Windows: CMake из командной строки

В Developer PowerShell for Visual Studio:

```powershell
git checkout lora_cpp
cd cpp
cmake --preset release
cmake --build --preset release
ctest --preset release
```

Для MSVC используются `/W4` и `/permissive-`.

Preset не фиксирует конкретный генератор CMake. На Windows CMake может выбрать
Visual Studio generator, а на Linux — Makefiles/Ninja в зависимости от
установленного окружения. Поле `configuration` в build/test preset позволяет
корректно работать и с multi-config генераторами Visual Studio.

## Windows: Visual Studio

Можно использовать один из двух вариантов.

### Вариант 1 — открыть CMake-проект

В Visual Studio выберите `Open -> Folder` и откройте каталог `cpp/` или весь
репозиторий. Visual Studio обнаружит `cpp/CMakeLists.txt` и
`cpp/CMakePresets.json` и сможет выполнить configure/build непосредственно
через CMake.

Этот вариант предпочтителен, потому что совпадает с CI и Linux-сборкой.

### Вариант 2 — solution

Для исходной Windows-разработки сохранён файл:

```text
cpp/LoRa.slnx
```

Он удобен для редактирования и отладки, однако корректность переносимой сборки
в первую очередь определяется `CMakeLists.txt`.

Локальные файлы Visual Studio (`.vs/`, `*.vcxproj.user`) не должны попадать в
Git и исключены через `.gitignore`.

## Демонстрационная программа

После Release-сборки через preset исполняемый файл находится внутри
`build/cpp-release/` (для multi-config генератора — дополнительно в каталоге
`Release`).

Linux, single-config generator:

```bash
./build/cpp-release/lora_chirp_demo
```

Windows/Visual Studio generator:

```powershell
.\build\cpp-release\Release\lora_chirp_demo.exe
```

Demo генерирует восемь upchirp со следующими параметрами:

```text
SF = 7
BW = 125 kHz
Fs = 500 kHz
samplesPerChip = Fs/BW = 4
samplesPerChirp = 2^SF * samplesPerChip = 512
```

Выход записывается в:

```text
chirp_sf7_bw125_fs500k_q13.pcm
```

`.pcm` является локальным производным файлом и исключён из Git.

## Основной API

Базовая точка входа — `ChirpModulator::generate_chirps`:

```cpp
ChirpModulator modulator;

auto up = modulator.generate_chirps(
    1,          // число chirp
    true,       // true = upchirp, false = downchirp
    7,          // SF
    125000.0,   // BW, Hz
    1000000.0   // Fs, Hz
);
```

Для этого примера:

```text
N = 2^7 = 128 chips
L = Fs/BW = 8 samples/chip
samplesPerChirp = N*L = 1024
```

Функция возвращает:

```cpp
std::vector<CPLX<short>>
```

с I/Q-компонентами в Q13.

## Формат комплексных отсчётов

Единичная амплитуда представляется масштабом:

```text
1.0 ↔ 8192
```

То есть примерно:

```text
I = round(real(x) * 8192)
Q = round(imag(x) * 8192)
```

Значение chirp остаётся близким к единичной окружности; небольшая амплитудная
ошибка определяется только квантованием I/Q.

Этот Q13 формат выбран для текущей C++ модели и не означает, что последующая
FPGA реализация обязана использовать именно такую разрядность.

## Соответствие MATLAB

`ChirpModulator::generate_chirps` использует тот же закон фазы, что и:

```text
model/matlab/+lora_phy/reference_chirp.m
```

Фаза MATLAB-модели задаётся как:

```text
phaseCycles[n] = 0.5*n^2/(N*L^2) - 0.5*n/L

N = 2^SF
L = samplesPerChip = Fs/BW
```

Комплексный upchirp:

```text
x_up[n] = exp(j*2*pi*phaseCycles[n])
```

Для downchirp:

```text
x_down[n] = conj(x_up[n])
```

Таким образом, C++ не использует отдельный экспериментальный frequency offset
для формирования chirp и повторяет MATLAB golden model непосредственно.

## Ограничение Fs/BW

Текущая реализация требует целого:

```text
L = Fs/BW
```

Это соответствует параметру `samplesPerChip` MATLAB-модели.

Корректные примеры:

| SF | BW | Fs | L | Отсчётов/chirp |
|---:|---:|---:|---:|---:|
| 7 | 125 kHz | 500 kHz | 4 | 512 |
| 7 | 125 kHz | 1 MHz | 8 | 1024 |
| 8 | 125 kHz | 1 MHz | 8 | 2048 |
| 7 | 250 kHz | 1 MHz | 4 | 512 |

Например:

```text
Fs = 1.024 MHz
BW = 125 kHz
Fs/BW = 8.192
```

не соответствует целому количеству отсчётов на chip и намеренно отклоняется.
Если такая частота дискретизации нужна реальному SDR-тракту, базовый CSS сигнал
следует генерировать на корректной целой chip-сетке, а затем отдельно выполнить
resampling. Это разделяет собственно CSS-модуляцию и преобразование частоты
дискретизации.

## DDS / FrequencyShift

Класс `FrequencyShift` является отдельным блоком и не используется для
искусственной коррекции базовой формулы chirp.

Он предназначен для операций вида:

```text
уже сформированный IQ сигнал
        ↓
frequency shift / CFO injection / компенсация
        ↓
сдвинутый IQ сигнал
```

После `reset()` первая комплексная фаза равна нулю. Положительный frequency
shift соответствует положительному вращению комплексной фазы.

Это важно для дальнейшего сопоставления C++ с NCO/DDS в FPGA.

## Golden regression

Главный regression-тест находится в:

```text
cpp/tests/test_chirp.cpp
```

Он использует уже существующий FPGA golden ROM:

```text
fpga/rom/lora_sf7_l8_reference_q10.mem
```

Этот ROM содержит авторитетный SF7/L8 reference upchirp для HDL matched-filter
тракта.

Проверяется цепочка:

```text
C++ Q13 chirp
      ↓
Q13 -> Q10
      ↓
сравнение sample-by-sample
      ↓
FPGA golden Q10 ROM
```

Из-за независимого округления при переходе Q13 -> Q10 допускается максимум:

```text
1 LSB Q10
```

Кроме самого golden-vector comparison тест проверяет:

- число отсчётов на chirp;
- комплексное сопряжение `upchirp/downchirp`;
- повторяемость нескольких последовательных chirp;
- сброс начальной фазы;
- отклонение нецелого `Fs/BW`;
- нулевую начальную фазу DDS;
- знак положительного frequency shift;
- защиту DDS от нулевой частоты дискретизации.

## Запуск только тестов

Через preset:

```bash
cd cpp
ctest --preset release
```

Без preset:

```bash
ctest --test-dir build/cpp --output-on-failure
```

Для Visual Studio/multi-config generator:

```powershell
ctest --test-dir build/cpp -C Release --output-on-failure
```

Успешный regression заканчивается сообщением вида:

```text
C++ chirp regression PASS; max Q10 error = 1 LSB
```

## GitHub Actions

Workflow:

```text
.github/workflows/cpp-ci.yml
```

выполняет CMake configure, build и CTest как минимум на:

- `ubuntu-latest`;
- `windows-latest`.

Это позволяет сразу обнаруживать:

- непереносимый Windows-only код;
- ошибки GCC/MSVC;
- проблемы CMake;
- расхождение C++ chirp с golden ROM.

## Где находится эталон

Для алгоритмической проверки источники располагаются следующим образом:

```text
MATLAB chirp:
model/matlab/+lora_phy/reference_chirp.m

C++ chirp:
cpp/LoRa/chirp_modulator.cpp

C++ regression:
cpp/tests/test_chirp.cpp

FPGA golden ROM:
fpga/rom/lora_sf7_l8_reference_q10.mem

HDL ROM wrapper:
fpga/wrappers/lora_reference_chirp_rom.v
```

Если формула chirp намеренно меняется, следует сначала определить новый golden
reference на MATLAB-уровне, затем обновить производные векторы и только после
этого принимать изменение C++/HDL.

## Следующие шаги

Логичное развитие C++ PHY после базового reference chirp:

1. `modulate_symbol(symbol)` — cyclic shift базового upchirp;
2. dechirp;
3. FFT и определение symbol bin;
4. packet preamble/sync;
5. сравнение symbol decisions с MATLAB;
6. fixed-point анализ перед переносом соответствующих блоков в HDL.

Такой порядок сохраняет C++ модель как независимую и проверяемую ступень между
MATLAB и FPGA, вместо появления отдельной несовместимой реализации LoRa PHY.
