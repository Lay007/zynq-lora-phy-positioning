cmake_minimum_required(VERSION 3.20)

project(zynq_lora_cpp LANGUAGES CXX)

add_library(lora_cpp_core
    LoRa/chirp_modulator.cpp
    LoRa/frequency_shift.cpp
)
target_include_directories(lora_cpp_core PUBLIC LoRa)
target_compile_features(lora_cpp_core PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(lora_cpp_core PRIVATE /W4 /permissive-)
else()
    target_compile_options(lora_cpp_core PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()

add_executable(lora_chirp_demo LoRa/LoRa.cpp)
target_link_libraries(lora_chirp_demo PRIVATE lora_cpp_core)

include(CTest)
if(BUILD_TESTING)
    add_executable(lora_cpp_tests tests/test_chirp.cpp)
    target_link_libraries(lora_cpp_tests PRIVATE lora_cpp_core)
    target_compile_definitions(lora_cpp_tests PRIVATE
        LORA_REFERENCE_ROM_PATH="${CMAKE_CURRENT_SOURCE_DIR}/../fpga/rom/lora_sf7_l8_reference_q10.mem"
    )

    if(MSVC)
        target_compile_options(lora_cpp_tests PRIVATE /W4 /permissive-)
    else()
        target_compile_options(lora_cpp_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
    endif()

    add_test(NAME lora_cpp_chirp_regression COMMAND lora_cpp_tests)
endif()
