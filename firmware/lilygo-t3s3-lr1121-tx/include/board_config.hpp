#pragma once

#include <Arduino.h>

namespace board {

constexpr int kRadioSclk = 5;
constexpr int kRadioMiso = 3;
constexpr int kRadioMosi = 6;
constexpr int kRadioCs = 7;
constexpr int kRadioReset = 8;
constexpr int kRadioBusy = 34;
constexpr int kRadioDio9 = 36;
// This T3-S3 LR1121 hardware reports use-case 0xF3. The low nibble is the
// documented LR1121 ID (0x03); the original diagnostic firmware accepts it.
constexpr uint8_t kRadioDeviceId = 0xF3;

constexpr int kI2cSda = 18;
constexpr int kI2cScl = 17;
constexpr uint8_t kOledAddress = 0x3C;

constexpr int kLed = 37;
constexpr int kButton = 0;
constexpr bool kLedActiveHigh = true;

#if defined(LILYGO_LR1121_PA_VERSION)
constexpr bool kPaVersion = true;
#else
constexpr bool kPaVersion = false;
#endif

inline void setLed(bool enabled) {
  digitalWrite(kLed, enabled == kLedActiveHigh ? HIGH : LOW);
}

}  // namespace board
