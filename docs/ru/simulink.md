# Simulink и путь к Verilog

[English modeling flow](../../model/README.md) · [English Simulink README](../../model/simulink/README.md)

## 1. MATLAB float

MATLAB определяет ожидаемое численное поведение без ограничений архитектуры HDL
и разрядности. Здесь фиксируются сигналы, искажения, синхронизация, PHY,
ToA/TDoA, метрики, failure cases и golden-векторы.

## 2. Simulink

Simulink преобразует проверенный алгоритм в потоковую архитектуру. Здесь явно
задаются sample rate, `valid`, framing, buffers, state, latency, rounding,
saturation и fixed-point типы. Источником реализации остаётся модель Simulink,
а не сгенерированный HDL.

Первый DUT:

```text
complex sample stream
    → dechirp
    → streaming FFT
    → magnitude / peak detector
    → symbol index + valid
```

DUT обязан определять clock/sample rate, backpressure, типы на границах,
overflow policy, pipeline latency, reset behavior и набор compile-time/tunable
LoRa-параметров.

## 3. HDL Coder

HDL Coder генерирует Verilog из единственного именованного DUT subsystem.
Testbench и визуализация остаются снаружи. Скрипты генерации, конфигурация,
модель и vector export версионируются вместе. Перед Vivado выполняются
fixed-point comparison и HDL cosimulation.

Сгенерированный алгоритмический Verilog не редактируется вручную. Изменение
поведения возвращается в MATLAB-требования и Simulink.

## 4. ZynqSDR

Vivado соединяет IP с AD936x, clock/reset, AXI, timestamp и ограничениями платы.
Каждая аппаратная запись ссылается на версии MATLAB/Simulink, конфигурацию HDL
и SHA-256 bitstream.
