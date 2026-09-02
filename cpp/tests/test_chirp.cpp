#include "chirp_modulator.h"
#include "frequency_shift.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#ifndef LORA_REFERENCE_ROM_PATH
#error "LORA_REFERENCE_ROM_PATH must point to the committed Q10 reference ROM"
#endif

namespace {
struct GoldenSample {
    int re;
    int im;
};

int signed16(std::uint32_t value) {
    value &= 0xffffu;
    return (value & 0x8000u)
        ? static_cast<int>(value) - 0x10000
        : static_cast<int>(value);
}

std::vector<GoldenSample> load_reference_rom() {
    std::ifstream input(LORA_REFERENCE_ROM_PATH);
    if (!input) {
        throw std::runtime_error("cannot open reference ROM");
    }

    std::vector<GoldenSample> samples;
    std::string line;
    while (std::getline(input, line)) {
        if (line.empty()) {
            continue;
        }

        const auto word = static_cast<std::uint32_t>(
            std::stoul(line, nullptr, 16));
        samples.push_back({signed16(word >> 16), signed16(word)});
    }
    return samples;
}

void require(bool condition, const char* message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}
}  // namespace

int main() {
    try {
        ChirpModulator modulator;
        const auto golden = load_reference_rom();
        const auto up = modulator.generate_chirps(
            1, true, 7, 125'000.0, 1'000'000.0);

        require(golden.size() == 1024, "unexpected reference ROM length");
        require(up.size() == golden.size(),
                "C++ chirp length differs from golden ROM");

        // FPGA ROM uses independently quantized Q10 values. The C++ reference
        // is Q13, so rescaling can differ by one Q10 LSB because of the two
        // independent rounding operations.
        int max_q10_error = 0;
        for (std::size_t index = 0; index < up.size(); ++index) {
            const int re_q10 = static_cast<int>(
                std::llround(up[index].re / 8.0));
            const int im_q10 = static_cast<int>(
                std::llround(up[index].im / 8.0));
            const int re_error = std::abs(re_q10 - golden[index].re);
            const int im_error = std::abs(im_q10 - golden[index].im);
            max_q10_error = std::max(
                max_q10_error, std::max(re_error, im_error));
        }
        require(max_q10_error <= 1,
                "C++ chirp differs from MATLAB/HDL golden ROM by more than one Q10 LSB");

        const auto down = modulator.generate_chirps(
            1, false, 7, 125'000.0, 1'000'000.0);
        require(down.size() == up.size(), "downchirp length mismatch");
        for (std::size_t index = 0; index < up.size(); ++index) {
            require(down[index].re == up[index].re,
                    "downchirp real part is not conjugated reference");
            require(down[index].im == -up[index].im,
                    "downchirp imaginary part is not conjugated reference");
        }

        const auto repeated = modulator.generate_chirps(
            2, true, 7, 125'000.0, 1'000'000.0);
        require(repeated.size() == 2 * up.size(),
                "repeated chirp length mismatch");
        for (std::size_t index = 0; index < up.size(); ++index) {
            require(
                repeated[index].re == repeated[index + up.size()].re &&
                repeated[index].im == repeated[index + up.size()].im,
                "chirp phase does not reset between repetitions");
        }

        bool invalid_ratio_rejected = false;
        try {
            (void)modulator.generate_chirps(
                1, true, 7, 125'000.0, 1'024'000.0);
        } catch (const std::invalid_argument&) {
            invalid_ratio_rejected = true;
        }
        require(invalid_ratio_rejected,
                "non-integer fs/bw must be rejected");

        FrequencyShift dds;
        dds.calculate_increment(0.25);
        const CPLX<short> unit{8192, 0};
        const auto dds0 = dds.shift(unit);
        const auto dds1 = dds.shift(unit);
        require(dds0.re == 8192 && dds0.im == 0,
                "DDS must start at zero phase");
        require(dds1.re == 0 && dds1.im == 8192,
                "positive DDS frequency has wrong sign");

        bool zero_rate_rejected = false;
        try {
            FrequencyShift invalid_dds(1, 0);
        } catch (const std::invalid_argument&) {
            zero_rate_rejected = true;
        }
        require(zero_rate_rejected,
                "DDS must reject zero sample rate");

        std::cout << "C++ chirp regression PASS; max Q10 error = "
                  << max_q10_error << " LSB\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "C++ chirp regression FAIL: "
                  << error.what() << '\n';
        return 1;
    }
}
