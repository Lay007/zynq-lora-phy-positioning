# C++ модель CSS chirp

Каталог содержит переносимую C++20-реализацию опорного CSS chirp и отдельный
DDS/frequency-shift блок. Visual Studio solution сохранён для работы в Windows,
а `CMakeLists.txt` используется для воспроизводимой сборки и CI.

## Соответствие MATLAB

`ChirpModulator::generate_chirps` использует тот же закон фазы, что и
`model/matlab/+lora_phy/reference_chirp.m`:

```text
phaseCycles[n] = 0.5*n^2/(N*L^2) - 0.5*n/L
N = 2^SF
L = Fs/BW
```

Для `downchirp` знак фазы инвертируется, то есть результат является комплексно
сопряжённым `upchirp`.

C++-выход квантован в Q13 с масштабом `8192 = 1.0`. Для прямого соответствия
MATLAB-модели отношение `Fs/BW` должно быть целым. Например:

- `SF7`, `BW=125 kHz`, `Fs=500 kHz` -> `L=4`, 512 отсчётов на chirp;
- `SF7`, `BW=125 kHz`, `Fs=1 MHz` -> `L=8`, 1024 отсчёта на chirp.

Конфигурации вроде `Fs=1.024 MHz`, `BW=125 kHz` дают `L=8.192` и намеренно
отклоняются. Такой сигнал сначала следует сформировать на целой сетке chip,
а затем при необходимости ресэмплировать отдельным блоком.

## Golden regression

Тест `cpp/tests/test_chirp.cpp` сравнивает C++ SF7/L8 upchirp с уже используемым
FPGA golden ROM:

```text
fpga/rom/lora_sf7_l8_reference_q10.mem
```

ROM является тем же опорным chirp, квантованным в Q10. C++ генерирует Q13,
поэтому после пересчёта Q13 -> Q10 допускается максимум один Q10 LSB из-за
независимого округления. Тест также проверяет:

- комплексное сопряжение `upchirp/downchirp`;
- сброс фазы между повторяющимися chirp;
- отклонение нецелого `Fs/BW`;
- нулевую начальную фазу DDS;
- знак положительного frequency shift;
- защиту DDS от нулевой частоты дискретизации.

## Сборка и тест

Из корня репозитория:

```bash
cmake -S cpp -B build/cpp -DCMAKE_BUILD_TYPE=Release
cmake --build build/cpp --config Release --parallel
ctest --test-dir build/cpp -C Release --output-on-failure
```

Демонстрационная программа `lora_chirp_demo` записывает восемь SF7/BW125/L4
upchirp в локальный файл `chirp_sf7_bw125_fs500k_q13.pcm`. Файл `.pcm` исключён
из Git.
