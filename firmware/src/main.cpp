// Smart Mobile-Based Solar-Powered Chicken Feeding System
// ESP32 DevKit V1 Firmware - Machine Integration Layer
// Aligned with HARDWARE_INTEGRATION_SPECIFICATION.md
//
// Subsystems:
//   - MG996R Servo Gate (GPIO 13)
//   - HX711 24-bit ADC Load Cell Scale (DOUT GPIO 16, SCK GPIO 17)
//   - HC-SR04 Ultrasonic Depth Sensor (TRIG GPIO 5, ECHO GPIO 18)
//   - DS3231 Real-Time Clock (I2C SDA GPIO 21, SCL GPIO 22)
//   - 12V Battery Voltage Divider into ADC (GPIO 34)

#include <Arduino.h>
#include <Wire.h>
#include <ESP32Servo.h>
#include <HX711.h>
#include <RTClib.h>
#include <ArduinoJson.h>
#include "config.h"

Servo gate;
HX711 scale;
RTC_DS3231 rtc;

static bool rtcOk = false;
static bool isDispensing = false;
static bool emergencyStopRequested = false;
static unsigned long lastFedTimestampMs = 0;
static float lastFedGrams = 0.0f;

float readFeedLevelPercent() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);
  unsigned long us = pulseIn(PIN_US_ECHO, HIGH, 30000UL);
  if (us == 0) return -1.0f;  // sensor error / out of range
  float cm = us * 0.0343f / 2.0f;
  float pct = (HOPPER_EMPTY_CM - cm) / (HOPPER_EMPTY_CM - HOPPER_FULL_CM) * 100.0f;
  return constrain(pct, 0.0f, 100.0f);
}

float readBatteryVolts() {
  return analogReadMilliVolts(PIN_BATTERY_ADC) / 1000.0f * BATTERY_DIVIDER_RATIO;
}

int calculateBatteryPercent(float volts) {
  float pct = (volts - 11.2f) / (12.8f - 11.2f) * 100.0f;
  return constrain((int)round(pct), 0, 100);
}

void printTelemetryJson(const char* statusStr) {
  float level = readFeedLevelPercent();
  float vbat = readBatteryVolts();
  int batPct = calculateBatteryPercent(vbat);
  float weight = scale.get_units(2);

  JsonDocument doc;
  doc["feedLevelPercent"] = level >= 0 ? level : 0.0f;
  doc["batteryVolts"] = round(vbat * 100.0f) / 100.0f;
  doc["batteryPercent"] = batPct;
  doc["currentWeightGrams"] = round(weight * 10.0f) / 10.0f;
  doc["status"] = statusStr;
  doc["lastHeartbeat"] = (uint64_t)millis();
  doc["lastFedTimestamp"] = (uint64_t)lastFedTimestampMs;
  doc["lastFedGrams"] = lastFedGrams;
  doc["isSolarCharging"] = (vbat > 12.6f);

  String output;
  serializeJson(doc, output);
  Serial.print("TELEMETRY:");
  Serial.println(output);
}

void emitFeedingLog(const char* triggerType, float targetGrams, float actualGrams, int durationSec, bool success) {
  float level = readFeedLevelPercent();
  float vbat = readBatteryVolts();

  JsonDocument doc;
  doc["id"] = "log_" + String(millis());
  doc["timestamp"] = (uint64_t)millis();
  doc["targetGrams"] = targetGrams;
  doc["actualGrams"] = round(actualGrams * 10.0f) / 10.0f;
  doc["durationSeconds"] = durationSec;
  doc["triggerType"] = triggerType;
  doc["isSuccess"] = success;
  doc["batteryVolts"] = round(vbat * 100.0f) / 100.0f;
  doc["feedLevelPercent"] = level >= 0 ? level : 0.0f;

  String output;
  serializeJson(doc, output);
  Serial.print("FEEDING_LOG:");
  Serial.println(output);
}

// Closed-loop dispensing: keep gate open until load cell reaches target
bool dispenseFeed(float targetGrams, const char* triggerType) {
  if (isDispensing) return false;

  float vbat = readBatteryVolts();
  if (vbat < BATTERY_LOW_VOLTS) {
    Serial.println("[ERROR] Dispense blocked: Low battery voltage (<11.5V)");
    return false;
  }

  isDispensing = true;
  emergencyStopRequested = false;

  scale.tare();
  gate.write(SERVO_OPEN_DEG);
  printTelemetryJson("dispensing");

  unsigned long startTime = millis();
  float currentWeight = 0.0f;

  while (currentWeight < targetGrams) {
    if (emergencyStopRequested) {
      gate.write(SERVO_CLOSED_DEG);
      isDispensing = false;
      Serial.println("[ABORT] Dispensing halted by emergency stop");
      emitFeedingLog(triggerType, targetGrams, currentWeight, (int)((millis() - startTime) / 1000), false);
      printTelemetryJson("idle");
      return false;
    }

    if (millis() - startTime > DISPENSE_TIMEOUT_MS) {
      gate.write(SERVO_CLOSED_DEG);
      isDispensing = false;
      Serial.printf("[ERROR] Dispense timeout (motor jam or hopper empty) at %.1f g\n", currentWeight);
      emitFeedingLog(triggerType, targetGrams, currentWeight, (int)((millis() - startTime) / 1000), false);
      printTelemetryJson("error");
      return false;
    }

    delay(100);
    currentWeight = scale.get_units(2);
  }

  gate.write(SERVO_CLOSED_DEG);
  int durationSec = (int)((millis() - startTime) / 1000);
  isDispensing = false;

  lastFedTimestampMs = millis();
  lastFedGrams = currentWeight;

  Serial.printf("[OK] Dispensed %.1f g in %d s\n", currentWeight, durationSec);
  emitFeedingLog(triggerType, targetGrams, currentWeight, durationSec, true);
  printTelemetryJson("idle");
  return true;
}

void handleCommand(const String& cmdJson) {
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, cmdJson);
  if (err) {
    Serial.printf("[ERROR] Invalid JSON command: %s\n", err.c_str());
    return;
  }

  const char* action = doc["action"] | "";
  float targetGrams = doc["targetGrams"] | DEFAULT_TARGET_GRAMS;

  if (strcmp(action, "DISPENSE") == 0) {
    dispenseFeed(targetGrams, "Manual");
  } else if (strcmp(action, "EMERGENCY_STOP") == 0 || strcmp(action, "STOP") == 0) {
    emergencyStopRequested = true;
    gate.write(SERVO_CLOSED_DEG);
    Serial.println("[CMD] Emergency stop executed");
  } else if (strcmp(action, "TARE_SCALE") == 0) {
    scale.tare();
    Serial.println("[CMD] Load cell tared to 0.0g");
    printTelemetryJson("idle");
  } else if (strcmp(action, "SYNC_CLOCK") == 0) {
    uint32_t epoch = doc["timestamp"] | 0;
    if (epoch > 0 && rtcOk) {
      rtc.adjust(DateTime(epoch));
      Serial.println("[CMD] DS3231 RTC clock synchronized");
    }
  } else if (strcmp(action, "RESTART") == 0) {
    Serial.println("[CMD] Rebooting ESP32...");
    delay(500);
    ESP.restart();
  } else {
    Serial.printf("[WARN] Unknown command action: %s\n", action);
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);

  gate.attach(PIN_SERVO);
  gate.write(SERVO_CLOSED_DEG);

  scale.begin(PIN_HX711_DOUT, PIN_HX711_SCK);
  scale.set_scale(LOADCELL_CAL_FACTOR);
  scale.tare();

  Wire.begin();
  rtcOk = rtc.begin();
  if (rtcOk && rtc.lostPower()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  }

  Serial.println("=================================================");
  Serial.println(" Smart Chicken Feeder - Machine Integration Ready ");
  Serial.println(" Commands accepted: JSON or 'f' for manual feed   ");
  Serial.println("=================================================");
  printTelemetryJson("idle");
}

void loop() {
  static unsigned long lastTelemetry = 0;
  if (millis() - lastTelemetry >= TELEMETRY_INTERVAL_MS && !isDispensing) {
    lastTelemetry = millis();
    float level = readFeedLevelPercent();
    float vbat = readBatteryVolts();

    const char* currentStatus = "idle";
    if (level >= 0 && level < LOW_FEED_PERCENT) currentStatus = "lowFeed";
    else if (vbat < BATTERY_LOW_VOLTS) currentStatus = "lowBattery";

    printTelemetryJson(currentStatus);
  }

  // Process incoming serial command (JSON or single-char shortcut)
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    if (input.length() > 0) {
      if (input.startsWith("{")) {
        handleCommand(input);
      } else if (input == "f") {
        dispenseFeed(DEFAULT_TARGET_GRAMS, "Manual (Serial)");
      } else if (input == "t") {
        scale.tare();
        Serial.println("[CMD] Load cell tared");
      } else if (input == "s") {
        emergencyStopRequested = true;
        gate.write(SERVO_CLOSED_DEG);
      }
    }
  }
}
