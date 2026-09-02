#pragma once
// Roark
#include "frequency_shift.h"
// c++
#include <vector>
#include <math.h>


class ChirpModulator {
public:

	/// <summary>
	/// —генерировать чирпы
	/// </summary>
	/// <param name="num_chirps"></param>
	/// <param name="up"></param>
	/// <param name="sf"></param>
	/// <param name="bw"></param>
	/// <param name="fs"></param>
	/// <returns></returns>
	std::vector<CPLX<short>> generate_chirps(int num_chirps = 8, bool up = true,
		int sf = 7, double bw = 125'000.0, double fs = 1'024'000.);

	std::vector<CPLX<short>> generate_chirps_2(int num_chirps = 8, bool up = true,
		int sf = 7, double bw = 125'000.0, double fs = 1'024'000.);

	ChirpModulator() : frequency_shift(0, 0) {};
	
private:

	FrequencyShift frequency_shift;

};

