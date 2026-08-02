#pragma once

#include <Arduino.h>

namespace board {

constexpr int kRadioSclk = 9;
constexpr int kRadioMiso = 11;
constexpr int kRadioMosi = 10;
constexpr int kRadioCs = 8;
constexpr int kRadioReset = 12;
constexpr int kRadioBusy = 13;
constexpr int kRadioDio1 = 14;

constexpr int kVextEnable = 36;
constexpr int kFemPower = 7;
constexpr int kFemEnable = 2;
constexpr int kGc1109PaSelect = 46;
constexpr int kKct8103Context = 5;

constexpr int kI2cSda = 17;
constexpr int kI2cScl = 18;
constexpr int kOledReset = 21;
constexpr uint8_t kOledAddress = 0x3C;

constexpr int kLed = 35;
constexpr int kButton = 0;
constexpr bool kLedActiveHigh = true;

inline void preparePowerAndRfFrontend() {
  pinMode(kVextEnable, OUTPUT);
  digitalWrite(kVextEnable, LOW);
  pinMode(kFemPower, OUTPUT);
  digitalWrite(kFemPower, HIGH);
  pinMode(kFemEnable, OUTPUT);
  digitalWrite(kFemEnable, HIGH);

  // V4.2 GC1109: keep CPS low so TX uses the bypass path.
  pinMode(kGc1109PaSelect, OUTPUT);
  digitalWrite(kGc1109PaSelect, LOW);

  // V4.3 KCT8103L uses this GPIO for its CTX input. Keep it low until the
  // exact PCB revision is confirmed; this firmware must not enable its PA.
  pinMode(kKct8103Context, OUTPUT);
  digitalWrite(kKct8103Context, LOW);

  pinMode(kOledReset, OUTPUT);
  digitalWrite(kOledReset, LOW);
  delay(20);
  digitalWrite(kOledReset, HIGH);
}

inline void setLed(bool enabled) {
  digitalWrite(kLed, enabled == kLedActiveHigh ? HIGH : LOW);
}

}  // namespace board
