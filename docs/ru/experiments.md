# Воспроизводимые эксперименты

[English version](../../experiments/README.md)

Для каждого run копируется подходящий шаблон:

```text
experiments/templates/phy-capture.yaml
experiments/templates/toa.yaml
experiments/templates/tdoa.yaml
        ↓ копирование и заполнение
experiments/runs/2026-08-01_phy_capture_001.yaml
        ↓ выполнение
artifacts/2026-08-01_phy_capture_001/
```

`artifacts/` и непроверенные большие IQ captures не добавляются в Git. Для
значимого эксперимента коммитятся заполненная конфигурация, компактные
таблицы/графики и SHA-256 raw data. Проверенную и пригодную для публикации
эталонную запись можно перенести в `captures/reference/`: raw IQ в этом каталоге
хранится через Git LFS и обязательно сопровождается манифестом происхождения.

## Обязательное происхождение данных

- точный repository commit и clean/dirty state;
- board, RFIC, firmware, bitstream и host software revision;
- waveform/RF settings с явными единицами;
- clock/epoch topology и calibration ID;
- координаты приёмников и coordinate frame для TDoA;
- random seed симуляции;
- raw paths и SHA-256;
- критерий приёмки, выбранный до запуска.

`phy-capture.yaml` используется для RTL-SDR/PlutoSDR записи, проверяющей MATLAB
packet model до timestamp experiments.

Raw result не редактируется. Если изменился алгоритм обработки, создаётся новый
analysis output, который ссылается на тот же immutable capture.

## Именование

Рекомендуемый ID:

```text
YYYY-MM-DD_<kind>_<path>_<sequence>
```

Примеры:

```text
2026-08-10_phy_capture_ota_001
2026-08-12_toa_cable_001
2026-08-20_tdoa_indoor_001
```

## Минимальный порядок выполнения

1. Зафиксировать objective и acceptance до записи.
2. Проверить repository commit и оборудование.
3. Заполнить config и назначить output directory.
4. Записать raw data без последующего изменения.
5. Посчитать SHA-256.
6. Запустить analysis из зафиксированной версии кода.
7. Сохранить метрики, графики и журнал отклонений.
8. Повторную обработку оформить новым output revision.
