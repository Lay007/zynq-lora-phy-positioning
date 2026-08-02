#include <Arduino.h>
#include <RadioLib.h>
#include <SPI.h>
#include <SSD1306Wire.h>
#include <Wire.h>

#include <array>
#include <cctype>
#include <cstdint>
#include <cstdlib>

#include "board_config.hpp"

namespace {

constexpr char kFirmwareVersion[] = "0.1.1";
constexpr size_t kMaxPayloadLength = 220;
constexpr size_t kCounterHeaderLength = 12;
constexpr uint32_t kButtonDebounceMs = 50;
constexpr uint32_t kRadioPowerUpDelayMs = 1500;

struct RadioProfile {
  float frequencyMhz = 868.1F;
  float bandwidthKhz = 125.0F;
  uint8_t spreadingFactor = 7;
  uint8_t codingRate = 5;
  uint8_t syncWord = 0x12;
  int8_t outputPowerDbm = 0;
  uint16_t preambleSymbols = 12;
  bool crcEnabled = true;
  bool iqInverted = false;
  uint32_t intervalMs = 500;
  size_t payloadLength = 32;
};

enum class PayloadMode {
  Counter,
  FixedHex,
};

class LilygoLR1121 : public LR1121 {
 public:
  explicit LilygoLR1121(Module* module) : LR1121(module) {
    chipType = board::kRadioDeviceId;
  }
};

LilygoLR1121 radio(new Module(
    board::kRadioCs,
    board::kRadioDio9,
    board::kRadioReset,
    board::kRadioBusy));
SSD1306Wire display(board::kOledAddress, board::kI2cSda, board::kI2cScl);

RadioProfile profile;
PayloadMode payloadMode = PayloadMode::Counter;
std::array<uint8_t, kMaxPayloadLength> fixedPayload{};
size_t fixedPayloadLength = 0;
uint32_t sequenceNumber = 0;
uint32_t lastTransmitMs = 0;
uint32_t lastButtonChangeMs = 0;
bool transmitterRunning = false;
bool previousButtonState = HIGH;
bool displayReady = false;
int16_t lastRadioState = RADIOLIB_ERR_NONE;
String serialLine;

const uint32_t standardRfSwitchPins[] = {
    RADIOLIB_LR11X0_DIO5,
    RADIOLIB_LR11X0_DIO6,
    RADIOLIB_NC,
    RADIOLIB_NC,
    RADIOLIB_NC,
};

const Module::RfSwitchMode_t standardRfSwitchTable[] = {
    {LR11x0::MODE_STBY, {LOW, LOW}},
    {LR11x0::MODE_RX, {HIGH, LOW}},
    {LR11x0::MODE_TX, {LOW, HIGH}},
    {LR11x0::MODE_TX_HP, {LOW, HIGH}},
    {LR11x0::MODE_TX_HF, {LOW, LOW}},
    {LR11x0::MODE_GNSS, {LOW, LOW}},
    {LR11x0::MODE_WIFI, {LOW, LOW}},
    END_OF_MODE_TABLE,
};

#if defined(LILYGO_LR1121_PA_VERSION)
const uint32_t paRfSwitchPins[] = {
    RADIOLIB_LR11X0_DIO5,
    RADIOLIB_LR11X0_DIO6,
    RADIOLIB_LR11X0_DIO7,
    RADIOLIB_LR11X0_DIO8,
    RADIOLIB_NC,
};

const Module::RfSwitchMode_t paLowBandRfSwitchTable[] = {
    {LR11x0::MODE_STBY, {LOW, LOW, LOW, LOW}},
    {LR11x0::MODE_TX, {LOW, HIGH, LOW, LOW}},
    {LR11x0::MODE_RX, {HIGH, LOW, LOW, LOW}},
    {LR11x0::MODE_TX_HP, {LOW, HIGH, LOW, LOW}},
    {LR11x0::MODE_TX_HF, {LOW, LOW, LOW, LOW}},
    {LR11x0::MODE_GNSS, {LOW, LOW, LOW, LOW}},
    {LR11x0::MODE_WIFI, {LOW, LOW, LOW, LOW}},
    END_OF_MODE_TABLE,
};

const Module::RfSwitchMode_t paHighBandRfSwitchTable[] = {
    {LR11x0::MODE_STBY, {LOW, LOW, LOW, LOW}},
    {LR11x0::MODE_TX, {LOW, LOW, LOW, HIGH}},
    {LR11x0::MODE_RX, {LOW, LOW, HIGH, LOW}},
    {LR11x0::MODE_TX_HP, {LOW, LOW, HIGH, LOW}},
    {LR11x0::MODE_TX_HF, {LOW, LOW, HIGH, LOW}},
    {LR11x0::MODE_GNSS, {LOW, LOW, LOW, HIGH}},
    {LR11x0::MODE_WIFI, {LOW, LOW, LOW, HIGH}},
    END_OF_MODE_TABLE,
};
#endif

void printHelp();
void printProfile();
void updateDisplay(const char* status);
bool applyProfile(const RadioProfile& requestedProfile);
void transmitOnce();

bool radioOk(int16_t state, const char* operation) {
  lastRadioState = state;
  if (state == RADIOLIB_ERR_NONE) {
    return true;
  }

  Serial.printf("ERR operation=%s state=%d\n", operation, state);
  updateDisplay("RADIO ERROR");
  return false;
}

void configureRfSwitch(float frequencyMhz) {
#if defined(LILYGO_LR1121_PA_VERSION)
  if (frequencyMhz >= 2400.0F) {
    radio.setRfSwitchTable(paRfSwitchPins, paHighBandRfSwitchTable);
  } else {
    radio.setRfSwitchTable(paRfSwitchPins, paLowBandRfSwitchTable);
  }
#else
  (void)frequencyMhz;
  radio.setRfSwitchTable(standardRfSwitchPins, standardRfSwitchTable);
#endif
}

bool isOutputPowerValid(const RadioProfile& requestedProfile) {
  int minimumPower = -9;
  int maximumPower = 22;

  if (requestedProfile.frequencyMhz >= 1900.0F) {
    minimumPower = -18;
    maximumPower = board::kPaVersion ? 0 : 13;
  }

  if (requestedProfile.outputPowerDbm < minimumPower ||
      requestedProfile.outputPowerDbm > maximumPower) {
    Serial.printf(
        "ERR output power %d dBm is outside safe range [%d, %d] dBm\n",
        requestedProfile.outputPowerDbm,
        minimumPower,
        maximumPower);
    return false;
  }
  return true;
}

bool applyProfile(const RadioProfile& requestedProfile) {
  if (!isOutputPowerValid(requestedProfile)) {
    return false;
  }

  if (!radioOk(radio.standby(), "standby")) {
    return false;
  }
  if (!radioOk(radio.setFrequency(requestedProfile.frequencyMhz), "setFrequency")) {
    return false;
  }

  configureRfSwitch(requestedProfile.frequencyMhz);

  const bool forceHighPowerPa = requestedProfile.frequencyMhz < 1000.0F;
  if (!radioOk(
          radio.setOutputPower(requestedProfile.outputPowerDbm, forceHighPowerPa),
          "setOutputPower")) {
    return false;
  }
  if (!radioOk(radio.setBandwidth(requestedProfile.bandwidthKhz), "setBandwidth")) {
    return false;
  }
  if (!radioOk(
          radio.setSpreadingFactor(requestedProfile.spreadingFactor),
          "setSpreadingFactor")) {
    return false;
  }
  if (!radioOk(radio.setCodingRate(requestedProfile.codingRate), "setCodingRate")) {
    return false;
  }
  if (!radioOk(radio.setSyncWord(requestedProfile.syncWord), "setSyncWord")) {
    return false;
  }
  if (!radioOk(
          radio.setPreambleLength(requestedProfile.preambleSymbols),
          "setPreambleLength")) {
    return false;
  }
  if (!radioOk(radio.explicitHeader(), "explicitHeader")) {
    return false;
  }
  if (!radioOk(
          radio.setCRC(requestedProfile.crcEnabled ? 2 : 0),
          "setCRC")) {
    return false;
  }
  if (!radioOk(radio.invertIQ(requestedProfile.iqInverted), "invertIQ")) {
    return false;
  }

  lastRadioState = RADIOLIB_ERR_NONE;
  return true;
}

void writeUint32LittleEndian(uint8_t* destination, uint32_t value) {
  destination[0] = static_cast<uint8_t>(value & 0xFFU);
  destination[1] = static_cast<uint8_t>((value >> 8U) & 0xFFU);
  destination[2] = static_cast<uint8_t>((value >> 16U) & 0xFFU);
  destination[3] = static_cast<uint8_t>((value >> 24U) & 0xFFU);
}

size_t buildPayload(std::array<uint8_t, kMaxPayloadLength>& payload) {
  if (payloadMode == PayloadMode::FixedHex) {
    for (size_t index = 0; index < fixedPayloadLength; ++index) {
      payload[index] = fixedPayload[index];
    }
    return fixedPayloadLength;
  }

  const size_t length = profile.payloadLength;
  payload[0] = 'Z';
  payload[1] = 'L';
  payload[2] = 'P';
  payload[3] = '1';
  writeUint32LittleEndian(&payload[4], sequenceNumber);
  writeUint32LittleEndian(&payload[8], millis());

  for (size_t index = kCounterHeaderLength; index < length; ++index) {
    payload[index] = static_cast<uint8_t>(sequenceNumber + index - kCounterHeaderLength);
  }
  return length;
}

void transmitOnce() {
  std::array<uint8_t, kMaxPayloadLength> payload{};
  const size_t payloadLength = buildPayload(payload);
  const uint32_t transmitStartMs = millis();

  board::setLed(true);
  const int16_t state = radio.transmit(payload.data(), payloadLength);
  board::setLed(false);

  lastRadioState = state;
  Serial.printf(
      "TX seq=%lu len=%u state=%d start_ms=%lu duration_ms=%lu\n",
      static_cast<unsigned long>(sequenceNumber),
      static_cast<unsigned int>(payloadLength),
      state,
      static_cast<unsigned long>(transmitStartMs),
      static_cast<unsigned long>(millis() - transmitStartMs));

  ++sequenceNumber;
  lastTransmitMs = millis();
  updateDisplay(state == RADIOLIB_ERR_NONE ? "TX OK" : "TX ERROR");
}

void updateDisplay(const char* status) {
  if (!displayReady) {
    return;
  }
  char line[32];
  display.clear();
  display.setTextAlignment(TEXT_ALIGN_LEFT);
  display.setFont(ArialMT_Plain_10);

  snprintf(
      line,
      sizeof(line),
      "%s %s",
      transmitterRunning ? "RUN" : "STOP",
      status);
  display.drawString(0, 0, line);

  snprintf(
      line,
      sizeof(line),
      "%.3f MHz  SF%u",
      profile.frequencyMhz,
      profile.spreadingFactor);
  display.drawString(0, 14, line);

  snprintf(
      line,
      sizeof(line),
      "BW %.1f  CR 4/%u",
      profile.bandwidthKhz,
      profile.codingRate);
  display.drawString(0, 28, line);

  snprintf(
      line,
      sizeof(line),
      "P %d dBm  SEQ %lu",
      profile.outputPowerDbm,
      static_cast<unsigned long>(sequenceNumber));
  display.drawString(0, 42, line);

  display.display();
}

bool parseOnOff(const String& value, bool& parsedValue) {
  String normalized = value;
  normalized.toLowerCase();
  normalized.trim();
  if (normalized == "on" || normalized == "1" || normalized == "true") {
    parsedValue = true;
    return true;
  }
  if (normalized == "off" || normalized == "0" || normalized == "false") {
    parsedValue = false;
    return true;
  }
  return false;
}

bool parseHexByte(const String& value, uint8_t& parsedValue) {
  char* end = nullptr;
  const long result = strtol(value.c_str(), &end, 0);
  if (end == value.c_str() || *end != '\0' || result < 0 || result > 255) {
    return false;
  }
  parsedValue = static_cast<uint8_t>(result);
  return true;
}

bool commitProfile(const RadioProfile& candidate) {
  const RadioProfile previousProfile = profile;
  profile = candidate;
  if (applyProfile(profile)) {
    printProfile();
    updateDisplay("PROFILE OK");
    return true;
  }

  Serial.println("ERR profile rejected; restoring previous radio settings");
  profile = previousProfile;
  applyProfile(profile);
  updateDisplay("PROFILE ERR");
  return false;
}

void handleSetCommand(const String& arguments) {
  const int separator = arguments.indexOf(' ');
  if (separator < 0) {
    Serial.println("ERR usage: set <field> <value>");
    return;
  }

  String field = arguments.substring(0, separator);
  String value = arguments.substring(separator + 1);
  field.toLowerCase();
  value.trim();

  RadioProfile candidate = profile;

  if (field == "freq") {
    candidate.frequencyMhz = value.toFloat();
  } else if (field == "bw") {
    candidate.bandwidthKhz = value.toFloat();
  } else if (field == "sf") {
    candidate.spreadingFactor = static_cast<uint8_t>(value.toInt());
  } else if (field == "cr") {
    candidate.codingRate = static_cast<uint8_t>(value.toInt());
  } else if (field == "power") {
    candidate.outputPowerDbm = static_cast<int8_t>(value.toInt());
  } else if (field == "preamble") {
    candidate.preambleSymbols = static_cast<uint16_t>(value.toInt());
  } else if (field == "sync") {
    uint8_t syncWord = 0;
    if (!parseHexByte(value, syncWord)) {
      Serial.println("ERR sync must be a byte such as 0x12");
      return;
    }
    candidate.syncWord = syncWord;
  } else if (field == "crc") {
    bool enabled = false;
    if (!parseOnOff(value, enabled)) {
      Serial.println("ERR crc expects on or off");
      return;
    }
    candidate.crcEnabled = enabled;
  } else if (field == "iq") {
    value.toLowerCase();
    if (value == "normal") {
      candidate.iqInverted = false;
    } else if (value == "inverted") {
      candidate.iqInverted = true;
    } else {
      Serial.println("ERR iq expects normal or inverted");
      return;
    }
  } else if (field == "interval") {
    const long interval = value.toInt();
    if (interval < 20) {
      Serial.println("ERR interval must be at least 20 ms");
      return;
    }
    profile.intervalMs = static_cast<uint32_t>(interval);
    printProfile();
    updateDisplay("INTERVAL OK");
    return;
  } else if (field == "length") {
    const long length = value.toInt();
    if (length < static_cast<long>(kCounterHeaderLength) ||
        length > static_cast<long>(kMaxPayloadLength)) {
      Serial.printf(
          "ERR length range is %u..%u bytes\n",
          static_cast<unsigned int>(kCounterHeaderLength),
          static_cast<unsigned int>(kMaxPayloadLength));
      return;
    }
    profile.payloadLength = static_cast<size_t>(length);
    payloadMode = PayloadMode::Counter;
    printProfile();
    updateDisplay("LENGTH OK");
    return;
  } else {
    Serial.println("ERR unknown field");
    return;
  }

  commitProfile(candidate);
}

bool decodeHexPayload(String encoded) {
  encoded.replace(" ", "");
  encoded.replace(":", "");
  encoded.replace("-", "");

  if (encoded.startsWith("0x") || encoded.startsWith("0X")) {
    encoded.remove(0, 2);
  }
  if (encoded.length() == 0 || (encoded.length() % 2) != 0) {
    return false;
  }

  const size_t byteCount = encoded.length() / 2;
  if (byteCount > kMaxPayloadLength) {
    return false;
  }

  for (size_t index = 0; index < byteCount; ++index) {
    const String byteText = encoded.substring(index * 2, index * 2 + 2);
    char* end = nullptr;
    const long value = strtol(byteText.c_str(), &end, 16);
    if (end == byteText.c_str() || *end != '\0' || value < 0 || value > 255) {
      return false;
    }
    fixedPayload[index] = static_cast<uint8_t>(value);
  }

  fixedPayloadLength = byteCount;
  payloadMode = PayloadMode::FixedHex;
  return true;
}

void handlePayloadCommand(String arguments) {
  arguments.trim();
  String normalized = arguments;
  normalized.toLowerCase();

  if (normalized == "counter") {
    payloadMode = PayloadMode::Counter;
    Serial.println("OK payload=counter");
    return;
  }

  if (normalized.startsWith("hex ")) {
    const String encoded = arguments.substring(4);
    if (!decodeHexPayload(encoded)) {
      Serial.printf(
          "ERR payload hex expects 1..%u bytes encoded as hexadecimal\n",
          static_cast<unsigned int>(kMaxPayloadLength));
      return;
    }
    Serial.printf(
        "OK payload=fixed_hex length=%u\n",
        static_cast<unsigned int>(fixedPayloadLength));
    return;
  }

  Serial.println("ERR usage: payload counter | payload hex <hex-bytes>");
}

void printProfile() {
  Serial.printf(
      "PROFILE freq_mhz=%.3f bw_khz=%.1f sf=%u cr=4/%u sync=0x%02X "
      "power_dbm=%d preamble=%u crc=%s iq=%s interval_ms=%lu "
      "payload=%s length=%u running=%s pa_board=%s firmware=%s\n",
      profile.frequencyMhz,
      profile.bandwidthKhz,
      profile.spreadingFactor,
      profile.codingRate,
      profile.syncWord,
      profile.outputPowerDbm,
      profile.preambleSymbols,
      profile.crcEnabled ? "on" : "off",
      profile.iqInverted ? "inverted" : "normal",
      static_cast<unsigned long>(profile.intervalMs),
      payloadMode == PayloadMode::Counter ? "counter" : "fixed_hex",
      static_cast<unsigned int>(
          payloadMode == PayloadMode::Counter ? profile.payloadLength : fixedPayloadLength),
      transmitterRunning ? "yes" : "no",
      board::kPaVersion ? "yes" : "no",
      kFirmwareVersion);
}

void printHelp() {
  Serial.println("Commands:");
  Serial.println("  show | help | version");
  Serial.println("  start | stop | send");
  Serial.println("  set freq <MHz>        e.g. set freq 868.1");
  Serial.println("  set bw <kHz>          62.5, 125, 250, 500");
  Serial.println("  set sf <5..12>");
  Serial.println("  set cr <5..8>         denominator of 4/x");
  Serial.println("  set power <dBm>");
  Serial.println("  set preamble <symbols>");
  Serial.println("  set sync <byte>       e.g. set sync 0x12");
  Serial.println("  set crc <on|off>");
  Serial.println("  set iq <normal|inverted>");
  Serial.println("  set interval <ms>");
  Serial.println("  set length <12..220>  counter-payload length");
  Serial.println("  payload counter");
  Serial.println("  payload hex <hex-bytes>");
  Serial.println("BOOT button toggles periodic transmission.");
}

void handleCommand(String line) {
  line.trim();
  if (line.isEmpty()) {
    return;
  }

  const int separator = line.indexOf(' ');
  String command = separator < 0 ? line : line.substring(0, separator);
  String arguments = separator < 0 ? "" : line.substring(separator + 1);
  command.toLowerCase();
  arguments.trim();

  if (command == "help") {
    printHelp();
  } else if (command == "show") {
    printProfile();
  } else if (command == "version") {
    Serial.printf("zynq-lora-lr1121-tx %s\n", kFirmwareVersion);
  } else if (command == "start") {
    transmitterRunning = true;
    lastTransmitMs = millis() - profile.intervalMs;
    Serial.println("OK transmitter started");
    updateDisplay("STARTED");
  } else if (command == "stop") {
    transmitterRunning = false;
    Serial.println("OK transmitter stopped");
    updateDisplay("STOPPED");
  } else if (command == "send") {
    transmitOnce();
  } else if (command == "set") {
    handleSetCommand(arguments);
  } else if (command == "payload") {
    handlePayloadCommand(arguments);
  } else {
    Serial.println("ERR unknown command; type help");
  }
}

void serviceSerial() {
  while (Serial.available() > 0) {
    const char character = static_cast<char>(Serial.read());
    if (character == '\r') {
      continue;
    }
    if (character == '\n') {
      handleCommand(serialLine);
      serialLine = "";
      continue;
    }
    if (serialLine.length() < 512) {
      serialLine += character;
    }
  }
}

void serviceButton() {
  const bool currentState = digitalRead(board::kButton);
  const uint32_t now = millis();

  if (currentState != previousButtonState && now - lastButtonChangeMs >= kButtonDebounceMs) {
    lastButtonChangeMs = now;
    previousButtonState = currentState;
    if (currentState == LOW) {
      transmitterRunning = !transmitterRunning;
      if (transmitterRunning) {
        lastTransmitMs = now - profile.intervalMs;
      }
      Serial.printf("OK transmitter %s by button\n", transmitterRunning ? "started" : "stopped");
      updateDisplay(transmitterRunning ? "STARTED" : "STOPPED");
    }
  }
}

}  // namespace

void setup() {
  pinMode(board::kLed, OUTPUT);
  board::setLed(false);
  pinMode(board::kButton, INPUT_PULLUP);

  Serial.begin(115200);
  const uint32_t serialWaitStart = millis();
  while (!Serial && millis() - serialWaitStart < 3000) {
    delay(10);
  }

  SPI.begin(
      board::kRadioSclk,
      board::kRadioMiso,
      board::kRadioMosi);

  // LR1121 needs time for its power and TCXO rails to settle after board boot.
  // LILYGO's reference examples wait 1500 ms before the first radio command.
  delay(kRadioPowerUpDelayMs);

  Serial.printf(
      "Initializing LILYGO T3S3 V1.2 LR1121 transmitter firmware %s...\n",
      kFirmwareVersion);

  const int16_t beginState = radio.begin(
      profile.frequencyMhz,
      profile.bandwidthKhz,
      profile.spreadingFactor,
      profile.codingRate,
      profile.syncWord,
      profile.outputPowerDbm,
      profile.preambleSymbols,
      3.0F);

  if (!radioOk(beginState, "begin")) {
    Serial.println("FATAL radio initialization failed");
    while (true) {
      board::setLed(true);
      delay(100);
      board::setLed(false);
      delay(900);
    }
  }

  configureRfSwitch(profile.frequencyMhz);
  if (!applyProfile(profile)) {
    Serial.println("FATAL default profile could not be applied");
    while (true) {
      board::setLed(true);
      delay(100);
      board::setLed(false);
      delay(100);
    }
  }

  // Initialize I2C peripherals only after the radio is known-good. This keeps
  // ESP32-S3 GPIO-matrix changes away from the first LR1121 SPI transaction.
  Wire.begin(board::kI2cSda, board::kI2cScl);
  display.init();
  display.flipScreenVertically();
  displayReady = true;

  Serial.println("READY type help for commands; transmitter is stopped by default");
  printProfile();
  updateDisplay("READY");
}

void loop() {
  serviceSerial();
  serviceButton();

  const uint32_t now = millis();
  if (transmitterRunning && now - lastTransmitMs >= profile.intervalMs) {
    transmitOnce();
  }

  delay(2);
}
