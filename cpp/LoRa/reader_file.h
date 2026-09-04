#pragma once
// c++
#include <string>
#include <fstream>
#include <vector>

template <typename T>
class ReaderFile {
public:

	ReaderFile(std::string name) : file(name, std::ios::binary) {};
	~ReaderFile() { file.close(); }

	/// <summary>
	/// Универсальный считыватель любого формата данных
	/// </summary>
	/// <param name="array">массив, куда будем читать данные</param>
	/// <param name="size">размер данных в элементах массива</param>
	/// <returns></returns>
	bool reader_data(std::vector<T>& stream, size_t size) {
		if (file)
			if (!file.eof()) {
				stream.resize(size);
				file.read(reinterpret_cast<char*>(stream.data()), size * sizeof(T));
				if (file.gcount() == size * sizeof(T))
					return true;
			}
		return false;
	}

private:
	std::ifstream file;
};
