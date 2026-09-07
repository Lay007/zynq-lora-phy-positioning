#pragma once
// c++
#include <string>
#include <fstream>
#include <vector>
#include <functional>

template <typename T>
class WriterFile {
public:

	WriterFile() {}

	WriterFile(std::string name) : file(name, std::ios::binary) {};

	~WriterFile() { file.close(); }

	/// <summary>
	/// Записать данные в bin файл
	/// </summary>
	/// <param name="iq_array">Набор данных</param>
	/// <returns></returns>
	bool write_data_bin(std::vector<T>& stream) {
		if (file.is_open()) {
			file.write(reinterpret_cast<char*>(stream.data()), sizeof(T) * stream.size());
			return true;
		}
		return false;
	}
	//  
private:
	std::ofstream file;
};

