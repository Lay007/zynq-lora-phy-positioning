#include "chirp_modulator.h"

std::vector<CPLX<short>> ChirpModulator::generate_chirps(int num_chirps, bool up,
	int sf, double bw, double fs) {
	std::vector<CPLX<short>>out;
	size_t up_sample_rate = fs / bw;
	size_t N = 1 << sf;
	double start_frequency = 0.;
	double speed = (1./ up_sample_rate) / (static_cast<double>(up_sample_rate * N));

	if (up) {
		//start_frequency = -0.5 / up_sample_rate;
        start_frequency = -0.0625;
	}
	else {
		start_frequency = 0.5 / up_sample_rate;
		speed = -speed;
	}
	frequency_shift.calculate_increment(start_frequency);
	//
	static char cnt = 0x00;
	double current_frequency = start_frequency;
	out.reserve(num_chirps * N * up_sample_rate);
	for (size_t i = 0; i < num_chirps; i++) {
		for (size_t j = 0; j < N * up_sample_rate; j++) {
			CPLX<short>iq{ 8192, 0 };
			frequency_shift.calculate_increment(current_frequency);
			iq = frequency_shift.shift(iq);
			out.push_back(iq);
			current_frequency += speed;
		}
		current_frequency = start_frequency;
        frequency_shift.reset();
	}
    //
    
    FrequencyShift shift_2(1, 16);
    shift_2.calculate_increment(0.03125);
    for (size_t i = 0; i < out.size(); i++)
        out[i] = shift_2.shift(out[i]);
    //
	return out;
}