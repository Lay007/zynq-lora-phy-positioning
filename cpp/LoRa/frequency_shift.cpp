#include "frequency_shift.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <stdexcept>

namespace {
constexpr double kPi = 3.141592653589793238462643383279502884;

short saturate_to_short(long long value) {
    const auto low = static_cast<long long>(std::numeric_limits<short>::min());
    const auto high = static_cast<long long>(std::numeric_limits<short>::max());
    return static_cast<short>(std::clamp(value, low, high));
}
}  // namespace

FrequencyShift::FrequencyShift() {
    build_dds_table();
}

FrequencyShift::FrequencyShift(int frequency_hz, int sample_rate_hz)
    : FrequencyShift() {
    calculate_increment(frequency_hz, sample_rate_hz);
}

void FrequencyShift::build_dds_table() {
    dds_phase_.resize(kPhaseTableSize);

    for (int index = 0; index < kPhaseTableSize; ++index) {
        const double phase = 2.0 * kPi * static_cast<double>(index) /
            static_cast<double>(kPhaseTableSize);
        dds_phase_[index].re = static_cast<int>(
            std::lround(std::cos(phase) * kAmplitudeScale));
        dds_phase_[index].im = static_cast<int>(
            std::lround(std::sin(phase) * kAmplitudeScale));
    }
}

void FrequencyShift::calculate_increment(int frequency_hz, int sample_rate_hz) {
    if (sample_rate_hz == 0) {
        throw std::invalid_argument("sample_rate_hz must be non-zero");
    }

    calculate_increment(static_cast<double>(frequency_hz) /
        static_cast<double>(sample_rate_hz));
}

void FrequencyShift::calculate_increment(double normalized_frequency) {
    increment_ = static_cast<int>(std::lround(
        static_cast<double>(kPhaseTableSize) * normalized_frequency));
}

int FrequencyShift::wrap_phase(int phase) {
    phase %= kPhaseTableSize;
    if (phase < 0) {
        phase += kPhaseTableSize;
    }
    return phase;
}

CPLX<short> FrequencyShift::shift(CPLX<short> input) {
    // Сначала выдаём отсчёт с текущей фазой. Поэтому после reset() первый
    // отсчёт имеет нулевую фазу и совпадает с MATLAB exp(j*0) = 1.
    const CPLX<int>& carrier = dds_phase_[current_phase_];

    const long long output_re =
        (static_cast<long long>(input.re) * carrier.re -
         static_cast<long long>(input.im) * carrier.im) /
        kAmplitudeScale;
    const long long output_im =
        (static_cast<long long>(input.im) * carrier.re +
         static_cast<long long>(input.re) * carrier.im) /
        kAmplitudeScale;

    current_phase_ = wrap_phase(current_phase_ + increment_);

    return CPLX<short>(saturate_to_short(output_re),
                       saturate_to_short(output_im));
}

void FrequencyShift::reset() {
    current_phase_ = 0;
}
