// c++
#include <iostream>
// Roark
#include "chirp_modulator.h"
#include "writer_file.h"
//
int main() {
	ChirpModulator chirp_modulator;
	WriterFile<CPLX<short>>writer_file_chirp("D:/signal/LoRa/chirp.pcm");
	std::vector<CPLX<short>>out_chirp = chirp_modulator.generate_chirps(8, true, 7, 1., 16.);
	writer_file_chirp.write_data_bin(out_chirp);
}