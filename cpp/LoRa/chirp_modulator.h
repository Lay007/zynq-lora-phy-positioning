#pragma once

#include "cplx.h"

#include <vector>

class ChirpModulator {
public:
    /// Сгенерировать повторяющиеся опорные CSS chirp в формате Q13.
    ///
    /// Частота дискретизации должна быть целым кратным BW, чтобы параметр
    /// samplesPerChip совпадал с MATLAB lora_phy.css_config.
    std::vector<CPLX<short>> generate_chirps(
        int num_chirps = 8,
        bool up = true,
        int sf = 7,
        double bw = 125'000.0,
        double fs = 500'000.0) const;
};
