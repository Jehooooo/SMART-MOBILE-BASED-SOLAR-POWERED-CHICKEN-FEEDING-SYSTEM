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
//   - Wi-Fi & Firebase Realtime Database REST Sync

#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <ESP32Servo.h>
#include <HX711.h>
#include <RTClib.h>
#include <ArduinoJson.h>
#include "config.h"

// Check if optional local secrets.h exists; otherwise default gracefully to offline mode
#if __has_include("secrets.h")
#include "secrets.h"
#define HAS_SECRETS 1
#else
#define HAS_SECRETS 0
#define WIFI_SSID ""
#define WIFI_PASSWORD ""
#define FIREBASE_API_KEY ""
#define FIREBASE_DB_URL ""
#endif

Servo gate;
HX711 scale;
RTC_DS3231 rtc;

static bool rtcOk = false;
static bool isDispensing = false;
static bool emergencyStopRequested = false;
static unsigned long lastFedTimestampMs = 0;
static float lastFedGrams = 0.0f;
static float currentCalFactor = LOADCELL_CAL_FACTOR;

// Forward declarations
void handleCommand(const String& cmdJson);
void printTelemetryJson(const char* statusStr);
void syncTelemetryToFirebase(const String& jsonPayload);
void syncLogToFirebase(const String& jsonPayload);

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

  // Sync to Firebase RTDB if online
  syncTelemetryToFirebase(output);
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

  // Sync to Firebase RTDB if online
  syncLogToFirebase(output);
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

// Timed dispensing: keep gate open for durationSeconds
bool dispenseFeedDuration(int durationSec, const char* triggerType) {
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
  unsigned long durationMs = (unsigned long)durationSec * 1000UL;

  while (millis() - startTime < durationMs) {
    if (emergencyStopRequested) {
      gate.write(SERVO_CLOSED_DEG);
      isDispensing = false;
      Serial.println("[ABORT] Dispensing halted by emergency stop");
      float currentWeight = scale.get_units(2);
      emitFeedingLog(triggerType, 0, currentWeight, (int)((millis() - startTime) / 1000), false);
      printTelemetryJson("idle");
      return false;
    }
    delay(50);
  }

  gate.write(SERVO_CLOSED_DEG);
  int actualDurationSec = (int)((millis() - startTime) / 1000);
  float dispensedWeight = scale.get_units(2);
  if (dispensedWeight < 0.0f) dispensedWeight = 0.0f;
  isDispensing = false;

  lastFedTimestampMs = millis();
  lastFedGrams = dispensedWeight;

  Serial.printf("[OK] Dispensed for %d s (approx %.1f g)\n", actualDurationSec, dispensedWeight);
  emitFeedingLog(triggerType, 0, dispensedWeight, actualDurationSec, true);
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
  int durationSec = doc["durationSeconds"] | doc["duration"] | 0;
  float targetGrams = doc["targetGrams"] | 0.0f;

  if (strcmp(action, "DISPENSE") == 0) {
    if (durationSec > 0 && targetGrams <= 90.0f && durationSec == 1) {
      // Diagnostic position sweep from app (0°, 45°, 90°)
      int deg = (int)round(targetGrams);
      deg = constrain(deg, 0, 90);
      gate.write(deg);
      Serial.printf("[CMD] Dispenser gate positioned to %d degrees\n", deg);
    } else if (durationSec > 0) {
      dispenseFeedDuration(durationSec, "Manual");
    } else if (targetGrams > 0.0f) {
      dispenseFeed(targetGrams, "Manual");
    } else {
      dispenseFeedDuration(5, "Manual");
    }
  } else if (strcmp(action, "EMERGENCY_STOP") == 0 || strcmp(action, "STOP") == 0) {
    emergencyStopRequested = true;
    gate.write(SERVO_CLOSED_DEG);
    Serial.println("[CMD] Emergency stop executed");
  } else if (strcmp(action, "TARE_SCALE") == 0) {
    scale.tare();
    Serial.println("[CMD] Load cell tared to 0.0g");
    printTelemetryJson("idle");
  } else if (strcmp(action, "CALIBRATE_SCALE") == 0) {
    float knownGrams = doc["targetGrams"] | 500.0f;
    if (knownGrams > 10.0f) {
      float rawUnits = scale.get_value(5);
      if (abs(rawUnits) > 100.0f) {
        currentCalFactor = rawUnits / knownGrams;
        scale.set_scale(currentCalFactor);
        Serial.printf("[CMD] Scale calibrated with %.1fg. New factor: %.2f\n", knownGrams, currentCalFactor);
      }
    }
    printTelemetryJson("idle");
  } else if (strcmp(action, "TEST_SERVO") == 0) {
    int angle = doc["angle"] | doc["targetGrams"] | 0;
    angle = constrain(angle, 0, 90);
    gate.write(angle);
    Serial.printf("[CMD] Servo test angle set to %d deg\n", angle);
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

// ---------- Wi-Fi & Firebase Realtime Database Sync ----------

void initWiFi() {
  if (strlen(WIFI_SSID) == 0) {
    Serial.println("[WIFI] No SSID configured. Running in serial/offline tethered mode.");
    return;
  }
  Serial.printf("[WIFI] Connecting to '%s'...\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
}

void checkWiFiReconnect() {
  if (strlen(WIFI_SSID) == 0) return;
  static unsigned long lastCheck = 0;
  if (millis() - lastCheck >= WIFI_RECONNECT_INTERVAL_MS) {
    lastCheck = millis();
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println("[WIFI] Connection lost. Attempting non-blocking reconnect...");
      WiFi.reconnect();
    }
  }
}

void syncTelemetryToFirebase(const String& jsonPayload) {
  if (WiFi.status() != WL_CONNECTED || strlen(FIREBASE_DB_URL) == 0) return;

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  String url = String(FIREBASE_DB_URL);
  if (!url.endsWith("/")) url += "/";
  url += "telemetry.json";

  if (https.begin(client, url)) {
    https.addHeader("Content-Type", "application/json");
    https.setTimeout(3000);
    int httpCode = https.PUT(jsonPayload);
    if (httpCode <= 0) {
      Serial.printf("[CLOUD ERROR] Telemetry sync failed: %s\n", https.errorToString(httpCode).c_str());
    }
    https.end();
  }
}

void syncLogToFirebase(const String& jsonPayload) {
  if (WiFi.status() != WL_CONNECTED || strlen(FIREBASE_DB_URL) == 0) return;

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  String url = String(FIREBASE_DB_URL);
  if (!url.endsWith("/")) url += "/";
  url += "logs.json";

  if (https.begin(client, url)) {
    https.addHeader("Content-Type", "application/json");
    https.setTimeout(4000);
    int httpCode = https.POST(jsonPayload);
    if (httpCode > 0) {
      Serial.printf("[CLOUD] Feeding log stored: HTTP %d\n", httpCode);
    }
    https.end();
  }
}

void pollFirebaseCommands() {
  if (WiFi.status() != WL_CONNECTED || strlen(FIREBASE_DB_URL) == 0 || isDispensing) return;

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  String url = String(FIREBASE_DB_URL);
  if (!url.endsWith("/")) url += "/";
  url += "commands/dispense.json";

  if (https.begin(client, url)) {
    https.setTimeout(2500);
    int httpCode = https.GET();
    if (httpCode == 200) {
      String payload = https.getString();
      if (payload.length() > 0 && payload != "null") {
        Serial.printf("[CLOUD] Received remote command: %s\n", payload.c_str());
        handleCommand(payload);

        // Clear command from Firebase to prevent duplicate execution
        https.end();
        if (https.begin(client, url)) {
          https.setTimeout(2000);
          https.sendRequest("DELETE");
          https.end();
        }
        return;
      }
    }
    https.end();
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);

  gate.attach(PIN_SERVO);
  gate.write(SERVO_CLOSED_DEG);

  scale.begin(PIN_HX711_DOUT, PIN_HX711_SCK);
  scale.set_scale(currentCalFactor);
  scale.tare();

  Wire.begin();
  rtcOk = rtc.begin();
  if (rtcOk && rtc.lostPower()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  }

  Serial.println("=================================================");
  Serial.println(" Smart Chicken Feeder - Machine Integration Ready ");
  Serial.println(" Connected to: Local Sensors + Cloud Sync Loop   ");
  Serial.println("=================================================");

  initWiFi();
  printTelemetryJson("idle");
}

void loop() {
  checkWiFiReconnect();

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

  static unsigned long lastCommandPoll = 0;
  if (millis() - lastCommandPoll >= COMMAND_POLL_INTERVAL_MS) {
    lastCommandPoll = millis();
    pollFirebaseCommands();
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

