#pragma once
// my
#include "cplx.h"
#include "constant.h"
// c++
#include <vector>
//
struct PairFrequency {
	int rf = 0;
	int sr = 1;

	// Конструктор по умолчанию (не обязательно, но полезно)
	PairFrequency() = default;

	// Конструктор с параметрами
	PairFrequency(int rf_val, int sr_val) : rf(rf_val), sr(sr_val) {}
};

class FrequencyShift {
public:

	FrequencyShift(int fn, int fs) {
		dds_ph.resize(pi2_ph);
		int one_gr_ph = pi2_ph / (M_PI * 2);
		for (unsigned int i = 0; i < pi2_ph; i++) {
			dds_ph[i].re = (int)(cos(double(i) / double(one_gr_ph)) * 8192);
			dds_ph[i].im = (int)(-sin(double(i) / double(one_gr_ph)) * 8192);
		}
		calculate_increment(fn, fs);
	}

	// Конструктор копирования
	FrequencyShift(const FrequencyShift& other)
		: pi2_ph(other.pi2_ph),
		dds_ph(other.dds_ph),
		carrier_shift(other.carrier_shift),
		increment(other.increment),
		current_ph(other.current_ph) {}

	// Оператор присваивания
	FrequencyShift& operator=(const FrequencyShift& other) {
		if (this != &other) {
			pi2_ph = other.pi2_ph;
			dds_ph = other.dds_ph;
			carrier_shift = other.carrier_shift;
			increment = other.increment;
			current_ph = other.current_ph;
		}
		return *this;
	}

	// Конструктор перемещения (если нужно)
	FrequencyShift(FrequencyShift&& other) noexcept
		: pi2_ph(other.pi2_ph),
		dds_ph(std::move(other.dds_ph)),
		carrier_shift(other.carrier_shift),
		increment(other.increment),
		current_ph(other.current_ph) {
		other.current_ph = 0;
	}

	// Оператор перемещения
	FrequencyShift& operator=(FrequencyShift&& other) noexcept {
		if (this != &other) {
			pi2_ph = other.pi2_ph;
			dds_ph = std::move(other.dds_ph);
			carrier_shift = other.carrier_shift;
			increment = other.increment;
			current_ph = other.current_ph;
			other.current_ph = 0;
		}
		return *this;
	}

	/// <summary>
	/// Смещение по частоте
	/// </summary>
	/// <param name="input"></param>
	/// <returns></returns>
	CPLX<short> shift(CPLX<short> input);

	/// <summary>
	/// Вычислить приращение фазы
	/// </summary>
	/// <param name="fn"></param>
	/// <param name="fs"></param>
	void calculate_increment(int fn, int fs) {
		increment = int(double(pi2_ph) * double(fn) / double(fs));
	}

	/// <summary>
	/// Вычислить приращение фазы
	/// </summary>
	/// <param name="n"></param>
	void calculate_increment(double n = 0.) {
		increment = int(double(pi2_ph) * n);
	}

	/// <summary>
	/// Сброс 
	/// </summary>
	void reset() { current_ph = 0; carrier_shift = { 8192, 0 };  }
		
private:
	int pi2_ph = 8192;
	std::vector<CPLX<int>>dds_ph;
	CPLX<int>carrier_shift = { 8192, 0 };
	int increment = 0;
	int current_ph = 0;
};

