#include <exception>
#include <iostream>

#include "chirp_modulator.h"
#include "writer_file.h"

int main() {
    try {
        constexpr int kSpreadingFactor = 7;
        constexpr double kBandwidthHz = 125'000.0;
        constexpr double kSampleRateHz = 500'000.0;
        constexpr int kChirpCount = 8;

        ChirpModulator chirp_modulator;
        auto chirps = chirp_modulator.generate_chirps(
            kChirpCount,
            true,
            kSpreadingFactor,
            kBandwidthHz,
            kSampleRateHz);

        WriterFile<CPLX<short>> writer("chirp_sf7_bw125_fs500k_q13.pcm");
        if (!writer.write_data_bin(chirps)) {
            std::cerr << "Не удалось открыть выходной PCM-файл.\n";
            return 1;
        }

        std::cout << "Сгенерировано " << chirps.size()
                  << " комплексных Q13-отсчётов.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "Ошибка генерации chirp: " << error.what() << '\n';
        return 1;
    }
}
