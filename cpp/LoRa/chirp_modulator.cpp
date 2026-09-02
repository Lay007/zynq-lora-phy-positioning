#include "chirp_modulator.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>
#include <stdexcept>

namespace {
constexpr double kPi = 3.141592653589793238462643383279502884;
constexpr double kAmplitudeScale = 8192.0;

short quantize_q13(double value) {
    const long long quantized = std::llround(value * kAmplitudeScale);
    const long long low = static_cast<long long>(std::numeric_limits<short>::min());
    const long long high = static_cast<long long>(std::numeric_limits<short>::max());
    return static_cast<short>(std::clamp(quantized, low, high));
}

std::size_t samples_per_chip(double bw, double fs) {
    if (!(bw > 0.0) || !(fs > 0.0)) {
        throw std::invalid_argument("bw and fs must be positive");
    }

    const double ratio = fs / bw;
    const long long rounded = std::llround(ratio);
    const double tolerance = 1e-12 * std::max(1.0, std::abs(ratio));

    if (rounded < 1 || std::abs(ratio - static_cast<double>(rounded)) > tolerance) {
        throw std::invalid_argument(
            "fs/bw must be an integer to match MATLAB samplesPerChip");
    }

    return static_cast<std::size_t>(rounded);
}
}  // namespace

std::vector<CPLX<short>> ChirpModulator::generate_chirps(
    int num_chirps,
    bool up,
    int sf,
    double bw,
    double fs) const {
    if (num_chirps < 0) {
        throw std::invalid_argument("num_chirps must be non-negative");
    }
    if (sf < 5 || sf > 12) {
        throw std::invalid_argument("sf must be in the range 5..12");
    }

    const std::size_t l = samples_per_chip(bw, fs);
    const std::size_t n_chips = std::size_t{1} << sf;
    const std::size_t samples_per_symbol = n_chips * l;

    std::vector<CPLX<short>> output;
    output.reserve(static_cast<std::size_t>(num_chirps) * samples_per_symbol);

    // Та же формула, что и в model/matlab/+lora_phy/reference_chirp.m:
    // phaseCycles = 0.5*n^2/(N*L^2) - 0.5*n/L
    for (int chirp_index = 0; chirp_index < num_chirps; ++chirp_index) {
        for (std::size_t sample_index = 0;
             sample_index < samples_per_symbol;
             ++sample_index) {
            const double n = static_cast<double>(sample_index);
            const double n_chips_double = static_cast<double>(n_chips);
            const double l_double = static_cast<double>(l);

            double phase_cycles =
                0.5 * n * n / (n_chips_double * l_double * l_double) -
                0.5 * n / l_double;
            if (!up) {
                phase_cycles = -phase_cycles;
            }

            const double phase = 2.0 * kPi * phase_cycles;
            output.emplace_back(
                quantize_q13(std::cos(phase)),
                quantize_q13(std::sin(phase)));
        }
    }

    return output;
}
