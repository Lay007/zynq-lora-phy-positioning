#pragma once

#include <Arduino.h>

namespace board {

enum class Revision {
  V42,
  V43,
  Unknown,
};

struct RevisionProbe {
  Revision revision;
  uint8_t highSamples;
  uint8_t sampleCount;
};

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

inline RevisionProbe detectRevision() {
  constexpr uint8_t sampleCount = 32;
  uint8_t highSamples = 0;

  // V4.3 connects GPIO5 to KCT8103L CTX and a 10 kOhm pull-down. V4.2
  // leaves GPIO5 unconnected, so the ESP32-S3 internal pull-up wins. This is
  // a passive logic-level probe: the FEM is still unpowered and no RF occurs.
  pinMode(kKct8103Context, INPUT_PULLUP);
  delay(10);
  for (uint8_t sample = 0; sample < sampleCount; ++sample) {
    highSamples += digitalRead(kKct8103Context) == HIGH ? 1 : 0;
    delayMicroseconds(100);
  }
  pinMode(kKct8103Context, INPUT);

  Revision revision = Revision::Unknown;
  if (highSamples == sampleCount) {
    revision = Revision::V42;
  } else if (highSamples == 0) {
    revision = Revision::V43;
  }
  return {revision, highSamples, sampleCount};
}

inline const char* revisionName(Revision revision) {
  switch (revision) {
    case Revision::V42:
      return "v4.2";
    case Revision::V43:
      return "v4.3";
    default:
      return "unknown";
  }
}

inline const char* femModeName(Revision revision) {
  switch (revision) {
    case Revision::V42:
      return "gc1109-bypass";
    case Revision::V43:
      return "kct8103l-bypass";
    default:
      return "blocked";
  }
}

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

  // V4.3 KCT8103L uses this GPIO for its CTX input. Keep it low outside a
  // V4.3 transmit operation; the external PA remains disabled.
  pinMode(kKct8103Context, OUTPUT);
  digitalWrite(kKct8103Context, LOW);

  pinMode(kOledReset, OUTPUT);
  digitalWrite(kOledReset, LOW);
  delay(20);
  digitalWrite(kOledReset, HIGH);
}

inline void setTransmitBypass(Revision revision, bool transmitting) {
  // V4.2: SX1262 DIO2 drives GC1109 CTX; GPIO46 is held low for CPS=0.
  // V4.3: SX1262 DIO2 drives KCT8103L CPS; GPIO5 drives CTX. CPS=1 with
  // CTX=1 selects the low-loss transmit bypass instead of the external PA.
  if (revision == Revision::V43) {
    digitalWrite(kKct8103Context, transmitting ? HIGH : LOW);
  }
}

inline void setLed(bool enabled) {
  digitalWrite(kLed, enabled == kLedActiveHigh ? HIGH : LOW);
}

}  // namespace board
