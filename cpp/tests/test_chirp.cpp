#include "chirp_modulator.h"
#include "frequency_shift.h"

#include <algorithm>
#include <array>
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

int q13_to_q10(short value) {
    return static_cast<int>(std::llround(value / 8.0));
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
            const int re_q10 = q13_to_q10(up[index].re);
            const int im_q10 = q13_to_q10(up[index].im);
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

        // MATLAB lora_phy.modulate_symbol performs:
        // circshift(reference_chirp, -symbol*samplesPerChip).
        // For SF7/L8 this is a left rotation of the committed Q10 golden ROM
        // by symbol*8 samples. Check representative symbols across the range.
        constexpr std::array<int, 5> kSymbols{0, 1, 17, 63, 127};
        constexpr std::size_t kSamplesPerChip = 8;
        int max_symbol_q10_error = 0;
        for (const int symbol : kSymbols) {
            const auto modulated = modulator.modulate_symbol(
                symbol, 7, 125'000.0, 1'000'000.0);
            require(modulated.size() == golden.size(),
                    "modulated symbol length mismatch");

            const std::size_t shift =
                static_cast<std::size_t>(symbol) * kSamplesPerChip;
            for (std::size_t index = 0; index < modulated.size(); ++index) {
                const auto& expected = golden[(index + shift) % golden.size()];
                const int re_error = std::abs(
                    q13_to_q10(modulated[index].re) - expected.re);
                const int im_error = std::abs(
                    q13_to_q10(modulated[index].im) - expected.im);
                max_symbol_q10_error = std::max(
                    max_symbol_q10_error, std::max(re_error, im_error));
            }
        }
        require(max_symbol_q10_error <= 1,
                "C++ LoRa symbol differs from MATLAB cyclic-shift golden reference by more than one Q10 LSB");

        bool negative_symbol_rejected = false;
        try {
            (void)modulator.modulate_symbol(
                -1, 7, 125'000.0, 1'000'000.0);
        } catch (const std::invalid_argument&) {
            negative_symbol_rejected = true;
        }
        require(negative_symbol_rejected,
                "negative LoRa symbol must be rejected");

        bool symbol_overflow_rejected = false;
        try {
            (void)modulator.modulate_symbol(
                128, 7, 125'000.0, 1'000'000.0);
        } catch (const std::invalid_argument&) {
            symbol_overflow_rejected = true;
        }
        require(symbol_overflow_rejected,
                "LoRa symbol >= 2^SF must be rejected");

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

        std::cout << "C++ chirp/symbol regression PASS; max chirp Q10 error = "
                  << max_q10_error
                  << " LSB; max symbol Q10 error = "
                  << max_symbol_q10_error << " LSB\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "C++ chirp/symbol regression FAIL: "
                  << error.what() << '\n';
        return 1;
    }
}
