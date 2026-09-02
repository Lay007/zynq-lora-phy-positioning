#pragma once

#include "cplx.h"

#include <vector>

class FrequencyShift {
public:
    FrequencyShift();
    FrequencyShift(int frequency_hz, int sample_rate_hz);

    /// Повернуть комплексный отсчёт на текущую фазу DDS.
    CPLX<short> shift(CPLX<short> input);

    /// Задать частоту в герцах при известной частоте дискретизации.
    void calculate_increment(int frequency_hz, int sample_rate_hz);

    /// Задать нормированную частоту в циклах на отсчёт.
    void calculate_increment(double normalized_frequency);

    /// Сбросить фазу DDS к нулю, сохранив текущее приращение.
    void reset();

    int phase_increment() const { return increment_; }
    int phase_index() const { return current_phase_; }

private:
    static constexpr int kPhaseTableSize = 8192;
    static constexpr int kAmplitudeScale = 8192;

    void build_dds_table();
    static int wrap_phase(int phase);

    std::vector<CPLX<int>> dds_phase_;
    int increment_ = 0;
    int current_phase_ = 0;
};
