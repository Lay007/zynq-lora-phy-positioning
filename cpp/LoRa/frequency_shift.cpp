#include "frequency_shift.h"

CPLX<short> FrequencyShift::shift(CPLX<short> input) {
	current_ph += abs(increment);
	current_ph %= pi2_ph;
	carrier_shift.re = dds_ph[current_ph].re;
	carrier_shift.im = dds_ph[current_ph].im;
	if (increment < 0)
		carrier_shift.im = -carrier_shift.im;
	//
	CPLX<int>output{ 0, 0 };
	output.re = input.re * carrier_shift.re - input.im * carrier_shift.im;
	output.im = input.im * carrier_shift.re + input.re * carrier_shift.im;
	//

	CPLX<short>out_short(output.re / 8192, output.im / 8192);

	return  CPLX<short>(output.re / 8192, output.im / 8192);
}