// Smart Mobile-Based Solar-Powered Chicken Feeding System
// ESP32 DevKit V1 Firmware - Hardened Machine Integration Layer
// Aligned with HARDWARE_INTEGRATION_SPECIFICATION.md
//
// Subsystems:
//   - MG996R Servo Gate (GPIO 13)
//   - HX711 24-bit ADC Load Cell Scale (DOUT GPIO 16, SCK GPIO 17)
//   - HC-SR04 Ultrasonic Depth Sensor (TRIG GPIO 5, ECHO GPIO 18)
//   - DS3231 Real-Time Clock (I2C SDA GPIO 21, SCL GPIO 22) + NTP Sync
//   - 12V Battery Voltage Divider into ADC (GPIO 34)
//   - NVS Flash Persistence (Schedules, Scale Calibration, Command Deduplication)
//   - Dual-Mode Wi-Fi (SoftAP + Station) & Authenticated Firebase RTDB REST Sync

#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <WebServer.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#include <time.h>
#include <sys/time.h>
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
#define FIREBASE_USER_EMAIL ""
#define FIREBASE_USER_PASSWORD ""
#endif

#ifndef FIREBASE_USER_EMAIL
#define FIREBASE_USER_EMAIL ""
#endif
#ifndef FIREBASE_USER_PASSWORD
#define FIREBASE_USER_PASSWORD ""
#endif

// HTTP Web Server for Direct Local Wi-Fi (SoftAP & Local Station)
WebServer server(HTTP_SERVER_PORT);

Servo gate;
HX711 scale;
RTC_DS3231 rtc;
Preferences prefs;

struct StoredSchedule {
  char id[32];
  char label[48];
  uint8_t hour;
  uint8_t minute;
  uint8_t durationSeconds;
  float targetGrams;
  bool isEnabled;
  uint8_t daysMask; // bit 0 = Mon (1) ... bit 6 = Sun (7)
};

static const size_t MAX_SCHEDULES = 16;
static StoredSchedule activeSchedules[MAX_SCHEDULES];
static size_t scheduleCount = 0;

static const size_t MAX_LOCAL_LOGS = 20;
static String localLogBuffer[MAX_LOCAL_LOGS];
static size_t localLogHead = 0;
static size_t localLogCount = 0;

static bool rtcOk = false;
static bool ntpConfigured = false;
static bool isDispensing = false;
static volatile bool emergencyStopRequested = false;

static bool loadCellHealthy = false;
static bool ultrasonicHealthy = true;
static uint8_t ultrasonicFailStreak = 0;
static float lastValidFeedLevel = -1.0f;
static String lastSensorError = "";

static uint64_t lastFedTimestampMs = 0ULL;
static float lastFedGrams = 0.0f;
static float currentCalFactor = LOADCELL_CAL_FACTOR;

static unsigned long servoTestAutoCloseAtMs = 0UL;
static String lastExecutedCommandId = "";
static String lastExecutedScheduleSlot = "";

// Firebase Authentication token cache
static String firebaseIdToken = "";
static unsigned long lastAuthRefreshMs = 0UL;

// Forward declarations
void handleCommand(const String& cmdJson, bool fromCloud);
void printTelemetryJson(const char* statusOverride = nullptr);
void syncTelemetryToFirebase(const String& jsonPayload);
void syncLogToFirebase(const String& logId, const String& jsonPayload);
void updateCommandAckInFirebase(
  const String& cmdId,
  const char* action,
  const char* status,
  float actualGrams,
  const char* errorMessage
);
bool authenticateFirebase(bool forceRefresh = false);
void syncSchedulesFromFirebase();
void checkAutonomousSchedules();

// ---------- Time & Clock Helpers ----------

static bool isValidEpochSec(time_t sec) {
  return sec >= 1700000000L; // >= Nov 2023
}

uint64_t getEpochMillis() {
  struct timeval tv;
  if (gettimeofday(&tv, nullptr) == 0 && isValidEpochSec(tv.tv_sec)) {
    return ((uint64_t)tv.tv_sec * 1000ULL) + ((uint64_t)tv.tv_usec / 1000ULL);
  }
  if (rtcOk) {
    DateTime now = rtc.now();
    uint32_t unixSec = now.unixtime();
    if (isValidEpochSec((time_t)unixSec)) {
      return ((uint64_t)unixSec * 1000ULL) + (uint64_t)(millis() % 1000UL);
    }
  }
  return 0ULL;
}

bool getLocalCalendarTime(struct tm* outTm) {
  time_t nowSec = time(nullptr);
  if (isValidEpochSec(nowSec)) {
    localtime_r(&nowSec, outTm);
    return true;
  }
  if (rtcOk) {
    DateTime dt = rtc.now();
    if (dt.year() >= 2024) {
      time_t rtcEpoch = (time_t)dt.unixtime() + GMT_OFFSET_SEC;
      gmtime_r(&rtcEpoch, outTm);
      return true;
    }
  }
  return false;
}

void syncNtpAndRtcIfConnected() {
  if (WiFi.status() != WL_CONNECTED) return;
  if (!ntpConfigured) {
    configTime(GMT_OFFSET_SEC, DAYLIGHT_OFFSET_SEC, NTP_SERVER_1, NTP_SERVER_2);
    ntpConfigured = true;
    Serial.println("[TIME] NTP synchronization configured.");
  }
  time_t nowSec = time(nullptr);
  static unsigned long lastRtcSyncMs = 0UL;
  if (rtcOk && isValidEpochSec(nowSec) && (lastRtcSyncMs == 0UL || millis() - lastRtcSyncMs > 3600000UL)) {
    rtc.adjust(DateTime((uint32_t)nowSec));
    lastRtcSyncMs = millis();
    Serial.println("[TIME] DS3231 RTC synchronized with NTP epoch.");
  }
}

// ---------- Non-Blocking Sensor Helpers ----------

bool safeScaleTare(uint8_t times = 5) {
  if (!scale.wait_ready_timeout(HX711_READY_TIMEOUT_MS)) {
    loadCellHealthy = false;
    lastSensorError = "hx711_timeout";
    Serial.println("[SENSOR WARN] HX711 DOUT not ready during tare.");
    return false;
  }
  scale.tare(times);
  loadCellHealthy = true;
  if (lastSensorError == "hx711_timeout") lastSensorError = "";
  return true;
}

bool safeReadScaleGrams(float* outGrams, uint8_t samples = 2) {
  if (!scale.wait_ready_timeout(HX711_READY_TIMEOUT_MS)) {
    loadCellHealthy = false;
    lastSensorError = "hx711_timeout";
    if (outGrams) *outGrams = 0.0f;
    return false;
  }
  float val = scale.get_units(samples);
  if (isnan(val) || isinf(val) || val < -250.0f || val > 10000.0f) {
    loadCellHealthy = false;
    lastSensorError = "hx711_out_of_range";
    if (outGrams) *outGrams = 0.0f;
    return false;
  }
  loadCellHealthy = true;
  if (lastSensorError.startsWith("hx711")) lastSensorError = "";
  if (outGrams) *outGrams = val;
  return true;
}

static float pingUltrasonicOnceCm() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);
  unsigned long us = pulseIn(PIN_US_ECHO, HIGH, 25000UL);
  if (us == 0) return -1.0f;
  float cm = us * 0.0343f / 2.0f;
  if (cm < 1.5f || cm > 200.0f) return -1.0f;
  return cm;
}

float readFeedLevelPercent() {
  float validSamples[3];
  int validCount = 0;
  for (int i = 0; i < 3; i++) {
    float cm = pingUltrasonicOnceCm();
    if (cm > 0.0f) {
      validSamples[validCount++] = cm;
    }
    if (i < 2) delayMicroseconds(1500);
  }

  if (validCount == 0) {
    if (ultrasonicFailStreak < 10) ultrasonicFailStreak++;
    if (ultrasonicFailStreak >= 3) {
      ultrasonicHealthy = false;
      lastSensorError = "ultrasonic_timeout";
    }
    return lastValidFeedLevel; // -1.0f if never valid, or last valid reading
  }

  // Average valid samples
  float avgCm = 0.0f;
  for (int i = 0; i < validCount; i++) avgCm += validSamples[i];
  avgCm /= (float)validCount;

  ultrasonicFailStreak = 0;
  ultrasonicHealthy = true;
  if (lastSensorError == "ultrasonic_timeout") lastSensorError = "";

  float pct = (HOPPER_EMPTY_CM - avgCm) / (HOPPER_EMPTY_CM - HOPPER_FULL_CM) * 100.0f;
  lastValidFeedLevel = constrain(pct, 0.0f, 100.0f);
  return lastValidFeedLevel;
}

float readBatteryVolts() {
  uint32_t mvSum = 0;
  for (int i = 0; i < 4; i++) {
    mvSum += analogReadMilliVolts(PIN_BATTERY_ADC);
  }
  return (mvSum / 4.0f) / 1000.0f * BATTERY_DIVIDER_RATIO;
}

int calculateBatteryPercent(float volts) {
  float pct = (volts - 11.2f) / (12.8f - 11.2f) * 100.0f;
  return constrain((int)round(pct), 0, 100);
}

const char* evaluateSystemStatus(float feedLevel, float vbat) {
  if (isDispensing) return "dispensing";
  if (!ultrasonicHealthy || lastSensorError.length() > 0) return "error";
  if (vbat < BATTERY_LOW_VOLTS) return "lowBattery";
  if (feedLevel >= 0.0f && feedLevel < (float)LOW_FEED_PERCENT) return "lowFeed";
  return "idle";
}

// ---------- Telemetry & Activity Logging ----------

String buildTelemetryJsonString(const char* statusOverride = nullptr) {
  float level = readFeedLevelPercent();
  float vbat = readBatteryVolts();
  int batPct = calculateBatteryPercent(vbat);
  float weight = 0.0f;
  safeReadScaleGrams(&weight, 1);

  const char* statusStr = statusOverride != nullptr
      ? statusOverride
      : evaluateSystemStatus(level, vbat);

  JsonDocument doc;
  doc["feedLevelPercent"] = level >= 0.0f ? round(level * 10.0f) / 10.0f : 0.0f;
  doc["batteryVolts"] = round(vbat * 100.0f) / 100.0f;
  doc["batteryPercent"] = batPct;
  doc["currentWeightGrams"] = round(max(0.0f, weight) * 10.0f) / 10.0f;
  doc["status"] = statusStr;
  doc["lastHeartbeat"] = getEpochMillis();
  doc["lastFedTimestamp"] = lastFedTimestampMs;
  doc["lastFedGrams"] = round(lastFedGrams * 10.0f) / 10.0f;
  doc["isSolarCharging"] = (vbat > 12.6f);
  if (lastSensorError.length() > 0) {
    doc["sensorError"] = lastSensorError;
  }

  String output;
  serializeJson(doc, output);
  return output;
}

void printTelemetryJson(const char* statusOverride) {
  String output = buildTelemetryJsonString(statusOverride);
  Serial.print("TELEMETRY:");
  Serial.println(output);
  syncTelemetryToFirebase(output);
}

void pushLocalLog(const String& logJson) {
  localLogBuffer[localLogHead] = logJson;
  localLogHead = (localLogHead + 1) % MAX_LOCAL_LOGS;
  if (localLogCount < MAX_LOCAL_LOGS) localLogCount++;
}

void emitFeedingLog(const char* triggerType, float targetGrams, float actualGrams, int durationSec, bool success) {
  float level = readFeedLevelPercent();
  float vbat = readBatteryVolts();
  uint64_t tsMs = getEpochMillis();
  String logId = tsMs > 0ULL
      ? ("log_" + String((unsigned long)(tsMs / 1000ULL)) + "_" + String(millis() % 1000UL))
      : ("log_boot_" + String(millis()));

  JsonDocument doc;
  doc["id"] = logId;
  doc["timestamp"] = tsMs > 0ULL ? tsMs : (uint64_t)millis();
  doc["targetGrams"] = round(targetGrams * 10.0f) / 10.0f;
  doc["actualGrams"] = round(max(0.0f, actualGrams) * 10.0f) / 10.0f;
  doc["durationSeconds"] = max(0, durationSec);
  doc["triggerType"] = triggerType;
  doc["isSuccess"] = success;
  doc["batteryVolts"] = round(vbat * 100.0f) / 100.0f;
  doc["feedLevelPercent"] = level >= 0.0f ? round(level * 10.0f) / 10.0f : 0.0f;

  String output;
  serializeJson(doc, output);
  pushLocalLog(output);

  Serial.print("FEEDING_LOG:");
  Serial.println(output);

  syncLogToFirebase(logId, output);
}

// ---------- Firebase URL & Auth Helpers ----------

static bool isConfiguredValue(const char* val) {
  if (val == nullptr || strlen(val) == 0) return false;
  if (strstr(val, "Your-") != nullptr || strstr(val, "YourGenerated") != nullptr) return false;
  return true;
}

String buildFirebaseUrl(const String& relativePath) {
  String url = String(FIREBASE_DB_URL);
  if (!url.endsWith("/")) url += "/";
  url += relativePath;
  if (firebaseIdToken.length() > 0) {
    url += (url.indexOf('?') >= 0 ? "&auth=" : "?auth=") + firebaseIdToken;
  }
  return url;
}

bool authenticateFirebase(bool forceRefresh) {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_API_KEY)) {
    return false;
  }
  if (!forceRefresh && firebaseIdToken.length() > 0 &&
      (millis() - lastAuthRefreshMs < AUTH_REFRESH_INTERVAL_MS)) {
    return true;
  }

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  bool usePasswordAuth = isConfiguredValue(FIREBASE_USER_EMAIL) &&
                         isConfiguredValue(FIREBASE_USER_PASSWORD) &&
                         strstr(FIREBASE_USER_EMAIL, "example") == nullptr;

  String endpoint = usePasswordAuth
      ? ("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" + String(FIREBASE_API_KEY))
      : ("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + String(FIREBASE_API_KEY));

  JsonDocument reqDoc;
  reqDoc["returnSecureToken"] = true;
  if (usePasswordAuth) {
    reqDoc["email"] = FIREBASE_USER_EMAIL;
    reqDoc["password"] = FIREBASE_USER_PASSWORD;
  }
  String reqBody;
  serializeJson(reqDoc, reqBody);

  bool ok = false;
  if (https.begin(client, endpoint)) {
    https.addHeader("Content-Type", "application/json");
    https.setTimeout(3500);
    int code = https.POST(reqBody);
    if (code == 200) {
      JsonDocument respDoc;
      if (!deserializeJson(respDoc, https.getString())) {
        const char* token = respDoc["idToken"] | "";
        if (strlen(token) > 0) {
          firebaseIdToken = String(token);
          lastAuthRefreshMs = millis();
          ok = true;
          Serial.println("[AUTH] Firebase ID token acquired.");
        }
      }
    } else if (usePasswordAuth) {
      // Fallback to Anonymous signUp if device email account is not created yet
      https.end();
      String anonUrl = "https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + String(FIREBASE_API_KEY);
      if (https.begin(client, anonUrl)) {
        https.addHeader("Content-Type", "application/json");
        https.setTimeout(3500);
        if (https.POST("{\"returnSecureToken\":true}") == 200) {
          JsonDocument respDoc;
          if (!deserializeJson(respDoc, https.getString())) {
            const char* token = respDoc["idToken"] | "";
            if (strlen(token) > 0) {
              firebaseIdToken = String(token);
              lastAuthRefreshMs = millis();
              ok = true;
              Serial.println("[AUTH] Firebase anonymous ID token acquired.");
            }
          }
        }
      }
    }
    https.end();
  }
  return ok;
}

static bool firebaseDeletePath(const char* pathJson) {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL)) return false;
  authenticateFirebase(false);
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;
  String url = buildFirebaseUrl(pathJson);
  bool ok = false;
  if (https.begin(client, url)) {
    https.setTimeout(2500);
    int code = https.sendRequest("DELETE");
    if (code == 401 && authenticateFirebase(true)) {
      https.end();
      if (https.begin(client, buildFirebaseUrl(pathJson))) {
        https.setTimeout(2500);
        code = https.sendRequest("DELETE");
      }
    }
    ok = (code >= 200 && code < 300);
    https.end();
  }
  return ok;
}

void updateCommandAckInFirebase(
  const String& cmdId,
  const char* action,
  const char* status,
  float actualGrams,
  const char* errorMessage
) {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL) || cmdId.length() == 0) return;
  authenticateFirebase(false);

  JsonDocument doc;
  doc["id"] = cmdId;
  doc["action"] = action;
  doc["status"] = status;
  doc["timestamp"] = getEpochMillis();
  doc["actualGrams"] = round(max(0.0f, actualGrams) * 10.0f) / 10.0f;
  if (errorMessage != nullptr && strlen(errorMessage) > 0) {
    doc["errorMessage"] = errorMessage;
  }

  String body;
  serializeJson(doc, body);

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;
  if (https.begin(client, buildFirebaseUrl("commands/latest.json"))) {
    https.addHeader("Content-Type", "application/json");
    https.setTimeout(2500);
    https.PUT(body);
    https.end();
  }
}

// ---------- Emergency Stop Polling Inside Active Dispense Loops ----------

bool checkCloudEmergencyStopFast() {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL)) return false;

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  const char* checkPaths[2] = {"commands/stop.json", "commands/dispense.json"};
  for (int i = 0; i < 2; i++) {
    if (https.begin(client, buildFirebaseUrl(checkPaths[i]))) {
      https.setTimeout(900);
      int code = https.GET();
      if (code == 200) {
        String body = https.getString();
        if (body.length() > 0 && body != "null") {
          JsonDocument doc;
          if (!deserializeJson(doc, body)) {
            const char* act = doc["action"] | "";
            if (strcmp(act, "STOP") == 0 || strcmp(act, "EMERGENCY_STOP") == 0) {
              https.end();
              firebaseDeletePath("commands/stop.json");
              firebaseDeletePath("commands/dispense.json");
              return true;
            }
          }
        }
      }
      https.end();
    }
  }
  return false;
}

void serviceEmergencyInputsDuringDispense(unsigned long* lastCloudStopCheckMs) {
  // 1. Service embedded HTTP server so local SoftAP POST /api/stop responds in <50ms
  server.handleClient();

  // 2. Check USB Serial emergency stop character
  while (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.equalsIgnoreCase("s") || line.equalsIgnoreCase("stop") ||
        line.indexOf("STOP") >= 0) {
      emergencyStopRequested = true;
      gate.write(SERVO_CLOSED_DEG);
      return;
    }
  }

  // 3. Periodically check Firebase RTDB for remote STOP signal (~900ms cadence)
  if (lastCloudStopCheckMs != nullptr && (millis() - *lastCloudStopCheckMs >= 900UL)) {
    *lastCloudStopCheckMs = millis();
    if (checkCloudEmergencyStopFast()) {
      emergencyStopRequested = true;
      gate.write(SERVO_CLOSED_DEG);
    }
  }
}

// ---------- Safe Closed-Loop & Timed Dispensing ----------

bool dispenseFeed(float targetGrams, const char* triggerType, String* outError = nullptr, float* outActualGrams = nullptr) {
  if (isDispensing) {
    if (outError) *outError = "Feeder is already dispensing";
    return false;
  }

  targetGrams = constrain(targetGrams, 1.0f, MAX_DISPENSE_GRAMS);

  float vbat = readBatteryVolts();
  if (vbat < BATTERY_CUTOFF_VOLTS) {
    lastSensorError = "low_battery_interlock";
    Serial.printf("[SAFETY] Dispense blocked: Battery %.2fV < %.1fV cutoff\n", vbat, BATTERY_CUTOFF_VOLTS);
    if (outError) *outError = "Battery below 11.2V safety cutoff";
    printTelemetryJson("lowBattery");
    return false;
  }

  // Verify load cell responds BEFORE opening gate for closed-loop weight dispensing
  if (!safeScaleTare(5)) {
    lastSensorError = "hx711_disconnected";
    Serial.println("[SAFETY] Dispense aborted before gate open: HX711 load cell not responding");
    if (outError) *outError = "HX711 load cell unresponsive";
    emitFeedingLog(triggerType, targetGrams, 0.0f, 0, false);
    printTelemetryJson("error");
    return false;
  }

  isDispensing = true;
  emergencyStopRequested = false;
  servoTestAutoCloseAtMs = 0UL;

  gate.write(SERVO_OPEN_DEG);
  printTelemetryJson("dispensing");

  unsigned long startTime = millis();
  unsigned long lastCloudStopCheck = millis();
  unsigned long lastProgressTelemetry = millis();
  float currentWeight = 0.0f;
  uint8_t consecutiveScaleErrors = 0;

  while (currentWeight < targetGrams) {
    serviceEmergencyInputsDuringDispense(&lastCloudStopCheck);

    if (emergencyStopRequested) {
      gate.write(SERVO_CLOSED_DEG);
      isDispensing = false;
      int elapsedSec = (int)((millis() - startTime) / 1000UL);
      Serial.println("[ABORT] Dispensing halted immediately by emergency stop");
      if (outActualGrams) *outActualGrams = max(0.0f, currentWeight);
      if (outError) *outError = "Aborted by emergency stop";
      emitFeedingLog("Manual (Aborted)", targetGrams, currentWeight, elapsedSec, false);
      printTelemetryJson("idle");
      return false;
    }

    float sampledWeight = 0.0f;
    if (safeReadScaleGrams(&sampledWeight, 2)) {
      consecutiveScaleErrors = 0;
      currentWeight = max(0.0f, sampledWeight);
    } else {
      consecutiveScaleErrors++;
      if (consecutiveScaleErrors >= 3) {
        gate.write(SERVO_CLOSED_DEG);
        isDispensing = false;
        lastSensorError = "hx711_mid_dispense_fault";
        Serial.println("[SAFETY] Gate closed: HX711 failed mid-dispense!");
        if (outActualGrams) *outActualGrams = max(0.0f, currentWeight);
        if (outError) *outError = "Load cell fault during dispensing";
        emitFeedingLog(triggerType, targetGrams, currentWeight, (int)((millis() - startTime) / 1000UL), false);
        printTelemetryJson("error");
        return false;
      }
    }

    unsigned long elapsedMs = millis() - startTime;

    // Stall / jam / empty hopper guard: prevent 30s uncontrolled open gate if weight isn't rising
    if (elapsedMs > DISPENSE_STALL_TIMEOUT_MS && currentWeight < MIN_FLOW_PROGRESS_GRAMS) {
      gate.write(SERVO_CLOSED_DEG);
      isDispensing = false;
      lastSensorError = "dispense_flow_stall";
      Serial.println("[SAFETY] Gate closed: No feed flow detected after 6s (hopper empty or gate jammed)");
      if (outActualGrams) *outActualGrams = currentWeight;
      if (outError) *outError = "No feed flow detected (jam or empty hopper)";
      emitFeedingLog(triggerType, targetGrams, currentWeight, (int)(elapsedMs / 1000UL), false);
      printTelemetryJson("error");
      return false;
    }

    if (elapsedMs > DISPENSE_TIMEOUT_MS) {
      gate.write(SERVO_CLOSED_DEG);
      isDispensing = false;
      lastSensorError = "dispense_timeout";
      Serial.printf("[ERROR] Dispense timeout at %.1f g\n", currentWeight);
      if (outActualGrams) *outActualGrams = currentWeight;
      if (outError) *outError = "Dispense timeout before target weight reached";
      emitFeedingLog(triggerType, targetGrams, currentWeight, (int)(elapsedMs / 1000UL), false);
      printTelemetryJson("error");
      return false;
    }

    if (millis() - lastProgressTelemetry >= 1500UL) {
      lastProgressTelemetry = millis();
      printTelemetryJson("dispensing");
    }

    delay(60);
  }

  gate.write(SERVO_CLOSED_DEG);
  int durationSec = max(1, (int)((millis() - startTime) / 1000UL));
  isDispensing = false;
  lastSensorError = "";

  lastFedTimestampMs = getEpochMillis();
  if (lastFedTimestampMs == 0ULL) lastFedTimestampMs = (uint64_t)millis();
  lastFedGrams = currentWeight;
  if (outActualGrams) *outActualGrams = currentWeight;

  Serial.printf("[OK] Dispensed %.1f g in %d s\n", currentWeight, durationSec);
  emitFeedingLog(triggerType, targetGrams, currentWeight, durationSec, true);
  printTelemetryJson();
  return true;
}

bool dispenseFeedDuration(int durationSec, const char* triggerType, float nominalTargetGrams = 0.0f, String* outError = nullptr, float* outActualGrams = nullptr) {
  if (isDispensing) {
    if (outError) *outError = "Feeder is already dispensing";
    return false;
  }

  durationSec = constrain(durationSec, 1, MAX_DISPENSE_DURATION_SEC);
  if (nominalTargetGrams <= 0.0f) nominalTargetGrams = durationSec * 20.0f;

  float vbat = readBatteryVolts();
  if (vbat < BATTERY_CUTOFF_VOLTS) {
    lastSensorError = "low_battery_interlock";
    Serial.printf("[SAFETY] Timed dispense blocked: Battery %.2fV < %.1fV cutoff\n", vbat, BATTERY_CUTOFF_VOLTS);
    if (outError) *outError = "Battery below 11.2V safety cutoff";
    printTelemetryJson("lowBattery");
    return false;
  }

  safeScaleTare(3); // non-blocking if HX711 absent in pure timed mode

  isDispensing = true;
  emergencyStopRequested = false;
  servoTestAutoCloseAtMs = 0UL;

  gate.write(SERVO_OPEN_DEG);
  printTelemetryJson("dispensing");

  unsigned long startTime = millis();
  unsigned long lastCloudStopCheck = millis();
  unsigned long durationMs = (unsigned long)durationSec * 1000UL;

  while (millis() - startTime < durationMs) {
    serviceEmergencyInputsDuringDispense(&lastCloudStopCheck);

    if (emergencyStopRequested) {
      gate.write(SERVO_CLOSED_DEG);
      isDispensing = false;
      float partialWeight = 0.0f;
      safeReadScaleGrams(&partialWeight, 2);
      partialWeight = max(0.0f, partialWeight);
      if (outActualGrams) *outActualGrams = partialWeight;
      if (outError) *outError = "Aborted by emergency stop";
      Serial.println("[ABORT] Timed dispensing halted immediately by emergency stop");
      emitFeedingLog("Manual (Aborted)", nominalTargetGrams, partialWeight, (int)((millis() - startTime) / 1000UL), false);
      printTelemetryJson("idle");
      return false;
    }
    delay(50);
  }

  gate.write(SERVO_CLOSED_DEG);
  int actualDurationSec = max(1, (int)((millis() - startTime) / 1000UL));
  float dispensedWeight = 0.0f;
  if (!safeReadScaleGrams(&dispensedWeight, 2) || dispensedWeight < 0.0f) {
    dispensedWeight = 0.0f;
  }
  isDispensing = false;

  lastFedTimestampMs = getEpochMillis();
  if (lastFedTimestampMs == 0ULL) lastFedTimestampMs = (uint64_t)millis();
  lastFedGrams = dispensedWeight;
  if (outActualGrams) *outActualGrams = dispensedWeight;

  Serial.printf("[OK] Dispensed for %d s (measured %.1f g)\n", actualDurationSec, dispensedWeight);
  emitFeedingLog(triggerType, nominalTargetGrams, dispensedWeight, actualDurationSec, true);
  printTelemetryJson();
  return true;
}

// ---------- Schedule NVS Persistence & Autonomous Execution ----------

void saveSchedulesToNvs() {
  JsonDocument doc;
  JsonArray arr = doc.to<JsonArray>();
  for (size_t i = 0; i < scheduleCount; i++) {
    JsonObject o = arr.add<JsonObject>();
    o["id"] = activeSchedules[i].id;
    o["label"] = activeSchedules[i].label;
    o["hour"] = activeSchedules[i].hour;
    o["minute"] = activeSchedules[i].minute;
    o["durationSeconds"] = activeSchedules[i].durationSeconds;
    o["targetGrams"] = activeSchedules[i].targetGrams;
    o["isEnabled"] = activeSchedules[i].isEnabled;
    o["daysMask"] = activeSchedules[i].daysMask;
  }
  String serialized;
  serializeJson(doc, serialized);
  prefs.putString("schedules", serialized);
}

static void parseSingleScheduleObject(const char* fallbackId, JsonVariantConst obj) {
  if (scheduleCount >= MAX_SCHEDULES || !obj.is<JsonObjectConst>()) return;
  StoredSchedule& s = activeSchedules[scheduleCount];
  const char* idStr = obj["id"] | fallbackId;
  strncpy(s.id, idStr ? idStr : "sch", sizeof(s.id) - 1);
  s.id[sizeof(s.id) - 1] = '\0';

  const char* labelStr = obj["label"] | "Scheduled Feed";
  strncpy(s.label, labelStr, sizeof(s.label) - 1);
  s.label[sizeof(s.label) - 1] = '\0';

  s.hour = (uint8_t)constrain((int)(obj["hour"] | 6), 0, 23);
  s.minute = (uint8_t)constrain((int)(obj["minute"] | 0), 0, 59);
  int dur = obj["durationSeconds"] | obj["duration"] | 5;
  s.durationSeconds = (uint8_t)constrain(dur, 1, MAX_DISPENSE_DURATION_SEC);
  float tgt = obj["targetGrams"] | (s.durationSeconds * 20.0f);
  s.targetGrams = constrain(tgt, 1.0f, MAX_DISPENSE_GRAMS);
  s.isEnabled = obj["isEnabled"] | true;

  if (obj["daysMask"].is<int>()) {
    s.daysMask = (uint8_t)(obj["daysMask"].as<int>() & 0x7F);
  } else if (obj["daysOfWeek"].is<JsonArrayConst>()) {
    uint8_t mask = 0;
    for (JsonVariantConst d : obj["daysOfWeek"].as<JsonArrayConst>()) {
      int day = d.as<int>(); // 1=Mon .. 7=Sun
      if (day >= 1 && day <= 7) mask |= (1 << (day - 1));
    }
    s.daysMask = mask == 0 ? 0x7F : mask;
  } else {
    s.daysMask = 0x7F; // every day
  }
  scheduleCount++;
}

bool updateSchedulesFromJson(const String& jsonStr, bool persistNvs = true) {
  if (jsonStr.length() == 0 || jsonStr == "null") {
    scheduleCount = 0;
    if (persistNvs) saveSchedulesToNvs();
    return true;
  }

  JsonDocument doc;
  if (deserializeJson(doc, jsonStr)) return false;

  scheduleCount = 0;
  if (doc.is<JsonArray>()) {
    int idx = 0;
    for (JsonVariantConst item : doc.as<JsonArrayConst>()) {
      String fb = "sch_" + String(idx++);
      parseSingleScheduleObject(fb.c_str(), item);
    }
  } else if (doc.is<JsonObject>()) {
    for (JsonPairConst kv : doc.as<JsonObjectConst>()) {
      parseSingleScheduleObject(kv.key().c_str(), kv.value());
    }
  }
  if (persistNvs) saveSchedulesToNvs();
  return true;
}

void loadPersistentStateFromNvs() {
  currentCalFactor = prefs.getFloat("calFactor", LOADCELL_CAL_FACTOR);
  if (isnan(currentCalFactor) || fabs(currentCalFactor) < 1.0f) {
    currentCalFactor = LOADCELL_CAL_FACTOR;
  }
  lastExecutedCommandId = prefs.getString("lastCmdId", "");
  lastExecutedScheduleSlot = prefs.getString("lastSchSlot", "");

  String savedSchedules = prefs.getString("schedules", "");
  if (savedSchedules.length() > 0) {
    updateSchedulesFromJson(savedSchedules, false);
    Serial.printf("[NVS] Restored %u feeding schedules and calFactor=%.2f\n",
                  (unsigned)scheduleCount, currentCalFactor);
  }
}

void syncSchedulesFromFirebase() {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL) || isDispensing) return;
  authenticateFirebase(false);

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  if (https.begin(client, buildFirebaseUrl("schedules.json"))) {
    https.setTimeout(3000);
    int code = https.GET();
    if (code == 401 && authenticateFirebase(true)) {
      https.end();
      if (https.begin(client, buildFirebaseUrl("schedules.json"))) {
        https.setTimeout(3000);
        code = https.GET();
      }
    }
    if (code == 200) {
      String body = https.getString();
      updateSchedulesFromJson(body, true);
    }
    https.end();
  }
}

void checkAutonomousSchedules() {
  if (isDispensing || scheduleCount == 0) return;

  struct tm localTm;
  if (!getLocalCalendarTime(&localTm)) return;

  // tm_wday: 0=Sun, 1=Mon..6=Sat -> convert to 1=Mon..7=Sun
  int weekday1Based = (localTm.tm_wday == 0) ? 7 : localTm.tm_wday;
  uint8_t todayBit = (uint8_t)(1 << (weekday1Based - 1));

  for (size_t i = 0; i < scheduleCount; i++) {
    const StoredSchedule& s = activeSchedules[i];
    if (!s.isEnabled) continue;
    if ((s.daysMask & todayBit) == 0) continue;
    if (s.hour == localTm.tm_hour && s.minute == localTm.tm_min) {
      char slotBuf[96];
      snprintf(slotBuf, sizeof(slotBuf), "%s_%04d%02d%02d_%02d%02d",
               s.id, localTm.tm_year + 1900, localTm.tm_mon + 1, localTm.tm_mday,
               s.hour, s.minute);
      String slotKey(slotBuf);

      if (slotKey == lastExecutedScheduleSlot) continue;

      lastExecutedScheduleSlot = slotKey;
      prefs.putString("lastSchSlot", lastExecutedScheduleSlot);

      String triggerLabel = "Schedule (" + String(s.label) + ")";
      Serial.printf("[SCHEDULE] Autonomous execution triggered: %s at %02u:%02u\n",
                    s.label, s.hour, s.minute);

      if (loadCellHealthy && s.targetGrams > 0.0f) {
        dispenseFeed(s.targetGrams, triggerLabel.c_str());
      } else {
        dispenseFeedDuration(s.durationSeconds, triggerLabel.c_str(), s.targetGrams);
      }
      break; // Execute one schedule per cycle cleanly
    }
  }
}

// ---------- Command Handler ----------

void handleCommand(const String& cmdJson, bool fromCloud) {
  JsonDocument doc;
  DeserializationError err = deserializeJson(doc, cmdJson);
  if (err) {
    Serial.printf("[ERROR] Invalid JSON command: %s\n", err.c_str());
    return;
  }

  String cmdId = String((const char*)(doc["id"] | ""));
  const char* action = doc["action"] | "";
  const char* status = doc["status"] | "pending";
  const char* triggerType = doc["triggerType"] | "Manual";
  String scheduleSlotKey = String((const char*)(doc["scheduleSlotKey"] | ""));
  int durationSec = doc["durationSeconds"] | doc["duration"] | 0;
  float targetGrams = doc["targetGrams"] | 0.0f;
  uint64_t cmdTsMs = doc["timestamp"] | 0ULL;

  // Emergency stop always preempts immediately regardless of timestamp/status
  if (strcmp(action, "EMERGENCY_STOP") == 0 || strcmp(action, "STOP") == 0) {
    emergencyStopRequested = true;
    gate.write(SERVO_CLOSED_DEG);
    servoTestAutoCloseAtMs = 0UL;
    Serial.println("[CMD] Emergency stop executed immediately");
    if (fromCloud && cmdId.length() > 0) {
      updateCommandAckInFirebase(cmdId, action, "completed", 0.0f, nullptr);
    }
    return;
  }

  if (fromCloud) {
    // 1. Only execute pending commands
    if (strcmp(status, "pending") != 0) {
      Serial.printf("[CMD SKIP] Ignoring non-pending command %s (status=%s)\n", cmdId.c_str(), status);
      return;
    }
    // 2. Prevent duplicate command ID replay across network retries or reboots
    if (cmdId.length() > 0 && cmdId == lastExecutedCommandId) {
      Serial.printf("[CMD SKIP] Duplicate command ID %s ignored\n", cmdId.c_str());
      return;
    }
    // 3. Prevent duplicate schedule slot execution if autonomous scheduler already ran
    if (scheduleSlotKey.length() > 0 && scheduleSlotKey == lastExecutedScheduleSlot) {
      Serial.printf("[CMD SKIP] Schedule slot %s already executed\n", scheduleSlotKey.c_str());
      updateCommandAckInFirebase(cmdId, action, "completed", lastFedGrams, "Already executed by onboard scheduler");
      return;
    }
    // 4. Reject stale commands when controller has valid epoch clock
    uint64_t nowMs = getEpochMillis();
    if (nowMs > 0ULL && cmdTsMs > 100000000000ULL && nowMs > cmdTsMs &&
        (nowMs - cmdTsMs) > COMMAND_MAX_AGE_MS) {
      Serial.printf("[SAFETY] Rejecting stale command %s (age=%llu ms > %lu ms)\n",
                    cmdId.c_str(), (unsigned long long)(nowMs - cmdTsMs), COMMAND_MAX_AGE_MS);
      updateCommandAckInFirebase(cmdId, action, "timeout", 0.0f, "Stale command rejected (>60s old)");
      return;
    }

    if (cmdId.length() > 0) {
      lastExecutedCommandId = cmdId;
      prefs.putString("lastCmdId", lastExecutedCommandId);
      updateCommandAckInFirebase(cmdId, action, "inProgress", 0.0f, nullptr);
    }
  }

  if (strcmp(action, "DISPENSE") == 0) {
    if (scheduleSlotKey.length() > 0) {
      lastExecutedScheduleSlot = scheduleSlotKey;
      prefs.putString("lastSchSlot", lastExecutedScheduleSlot);
    }
    String execErr = "";
    float actualG = 0.0f;
    bool ok = false;
    if (durationSec > 0 && targetGrams <= 0.0f) {
      ok = dispenseFeedDuration(durationSec, triggerType, durationSec * 20.0f, &execErr, &actualG);
    } else if (targetGrams > 0.0f && loadCellHealthy) {
      ok = dispenseFeed(targetGrams, triggerType, &execErr, &actualG);
    } else if (durationSec > 0) {
      ok = dispenseFeedDuration(durationSec, triggerType, targetGrams, &execErr, &actualG);
    } else if (targetGrams > 0.0f) {
      ok = dispenseFeed(targetGrams, triggerType, &execErr, &actualG);
    } else {
      ok = dispenseFeedDuration(5, triggerType, 100.0f, &execErr, &actualG);
    }
    if (fromCloud && cmdId.length() > 0) {
      const char* finalState = ok
          ? "completed"
          : (emergencyStopRequested ? "aborted" : "failed");
      updateCommandAckInFirebase(cmdId, action, finalState, actualG, execErr.c_str());
    }
  } else if (strcmp(action, "SERVO_TEST") == 0 || strcmp(action, "TEST_SERVO") == 0) {
    int angle = doc["servoAngle"] | doc["angle"] | (int)round(targetGrams);
    angle = constrain(angle, SERVO_CLOSED_DEG, SERVO_OPEN_DEG);
    gate.write(angle);
    servoTestAutoCloseAtMs = (angle > SERVO_CLOSED_DEG) ? (millis() + SERVO_TEST_AUTO_CLOSE_MS) : 0UL;
    Serial.printf("[CMD] Servo bench angle set to %d deg\n", angle);
    if (fromCloud && cmdId.length() > 0) {
      updateCommandAckInFirebase(cmdId, action, "completed", 0.0f, nullptr);
    }
  } else if (strcmp(action, "TARE_SCALE") == 0) {
    bool ok = safeScaleTare(8);
    printTelemetryJson();
    if (fromCloud && cmdId.length() > 0) {
      updateCommandAckInFirebase(cmdId, action, ok ? "completed" : "failed", 0.0f,
                                 ok ? nullptr : "HX711 load cell not responding");
    }
  } else if (strcmp(action, "CALIBRATE_SCALE") == 0) {
    float knownGrams = doc["targetGrams"] | 500.0f;
    bool ok = false;
    if (knownGrams > 10.0f && scale.wait_ready_timeout(HX711_READY_TIMEOUT_MS)) {
      float rawUnits = scale.get_value(5);
      if (fabs(rawUnits) > 100.0f) {
        currentCalFactor = rawUnits / knownGrams;
        scale.set_scale(currentCalFactor);
        prefs.putFloat("calFactor", currentCalFactor);
        loadCellHealthy = true;
        ok = true;
        Serial.printf("[CMD] Scale calibrated with %.1fg. Saved NVS factor: %.2f\n", knownGrams, currentCalFactor);
      }
    }
    printTelemetryJson();
    if (fromCloud && cmdId.length() > 0) {
      updateCommandAckInFirebase(cmdId, action, ok ? "completed" : "failed", 0.0f,
                                 ok ? nullptr : "Calibration failed: place reference weight and check HX711");
    }
  } else if (strcmp(action, "SYNC_CLOCK") == 0) {
    uint64_t rawTs = doc["timestamp"] | 0ULL;
    uint32_t epochSec = (rawTs > 100000000000ULL) ? (uint32_t)(rawTs / 1000ULL) : (uint32_t)rawTs;
    bool ok = false;
    if (isValidEpochSec((time_t)epochSec)) {
      struct timeval tv = { .tv_sec = (time_t)epochSec, .tv_usec = 0 };
      settimeofday(&tv, nullptr);
      if (rtcOk) {
        rtc.adjust(DateTime(epochSec));
      }
      ok = true;
      Serial.printf("[CMD] Clock synchronized to epoch %lu\n", (unsigned long)epochSec);
    }
    if (fromCloud && cmdId.length() > 0) {
      updateCommandAckInFirebase(cmdId, action, ok ? "completed" : "failed", 0.0f,
                                 ok ? nullptr : "Invalid epoch timestamp");
    }
  } else if (strcmp(action, "RESTART") == 0) {
    if (fromCloud && cmdId.length() > 0) {
      updateCommandAckInFirebase(cmdId, action, "completed", 0.0f, nullptr);
    }
    Serial.println("[CMD] Safe controller restart requested...");
    gate.write(SERVO_CLOSED_DEG);
    delay(400);
    ESP.restart();
  } else {
    Serial.printf("[WARN] Unknown command action: %s\n", action);
    if (fromCloud && cmdId.length() > 0) {
      updateCommandAckInFirebase(cmdId, action, "failed", 0.0f, "Unknown command action");
    }
  }
}

// ---------- Direct Wi-Fi WebServer & SoftAP REST API ----------

void setupWebServer() {
  server.on("/api/telemetry", HTTP_GET, []() {
    String out = buildTelemetryJsonString();
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", out);
  });

  server.on("/api/dispense", HTTP_POST, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    if (isDispensing) {
      server.send(409, "application/json", "{\"status\":\"busy\",\"message\":\"Dispensing in progress\"}");
      return;
    }
    int durationSec = 5;
    float targetGrams = 0.0f;
    if (server.hasArg("plain")) {
      JsonDocument doc;
      if (!deserializeJson(doc, server.arg("plain"))) {
        durationSec = doc["durationSeconds"] | doc["duration"] | 5;
        targetGrams = doc["targetGrams"] | 0.0f;
      }
    }
    if (server.hasArg("durationSeconds")) durationSec = server.arg("durationSeconds").toInt();
    if (server.hasArg("targetGrams")) targetGrams = server.arg("targetGrams").toFloat();

    float vbat = readBatteryVolts();
    if (vbat < BATTERY_CUTOFF_VOLTS) {
      server.send(422, "application/json", "{\"status\":\"error\",\"message\":\"Battery below 11.2V safety cutoff\"}");
      return;
    }

    server.send(200, "application/json", "{\"status\":\"ok\",\"message\":\"Dispensing initiated\"}");

    if (targetGrams > 0.0f && loadCellHealthy) {
      dispenseFeed(targetGrams, "Direct Local");
    } else {
      dispenseFeedDuration(durationSec, "Direct Local", targetGrams);
    }
  });

  server.on("/api/stop", HTTP_POST, []() {
    emergencyStopRequested = true;
    gate.write(SERVO_CLOSED_DEG);
    servoTestAutoCloseAtMs = 0UL;
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", "{\"status\":\"ok\",\"message\":\"Emergency stop executed\"}");
  });

  server.on("/api/tare", HTTP_POST, []() {
    bool ok = safeScaleTare(8);
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(ok ? 200 : 503, "application/json",
                ok ? "{\"status\":\"ok\",\"message\":\"Scale tared to 0.0g\"}"
                   : "{\"status\":\"error\",\"message\":\"HX711 load cell not responding\"}");
  });

  server.on("/api/calibrate", HTTP_POST, []() {
    float knownGrams = 500.0f;
    if (server.hasArg("plain")) {
      JsonDocument doc;
      if (!deserializeJson(doc, server.arg("plain"))) {
        knownGrams = doc["targetGrams"] | 500.0f;
      }
    }
    if (server.hasArg("targetGrams")) knownGrams = server.arg("targetGrams").toFloat();

    bool ok = false;
    if (knownGrams > 10.0f && scale.wait_ready_timeout(HX711_READY_TIMEOUT_MS)) {
      float rawUnits = scale.get_value(5);
      if (fabs(rawUnits) > 100.0f) {
        currentCalFactor = rawUnits / knownGrams;
        scale.set_scale(currentCalFactor);
        prefs.putFloat("calFactor", currentCalFactor);
        loadCellHealthy = true;
        ok = true;
      }
    }
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(ok ? 200 : 422, "application/json",
                "{\"status\":\"" + String(ok ? "ok" : "error") + "\",\"factor\":" + String(currentCalFactor, 2) + "}");
  });

  server.on("/api/servo", HTTP_POST, []() {
    int angle = 0;
    if (server.hasArg("plain")) {
      JsonDocument doc;
      if (!deserializeJson(doc, server.arg("plain"))) {
        angle = doc["servoAngle"] | doc["angle"] | doc["targetGrams"] | 0;
      }
    }
    if (server.hasArg("angle")) angle = server.arg("angle").toInt();
    angle = constrain(angle, SERVO_CLOSED_DEG, SERVO_OPEN_DEG);
    gate.write(angle);
    servoTestAutoCloseAtMs = (angle > SERVO_CLOSED_DEG) ? (millis() + SERVO_TEST_AUTO_CLOSE_MS) : 0UL;
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", "{\"status\":\"ok\",\"angle\":" + String(angle) + "}");
  });

  server.on("/api/sync-clock", HTTP_POST, []() {
    uint64_t rawTs = 0ULL;
    if (server.hasArg("plain")) {
      JsonDocument doc;
      if (!deserializeJson(doc, server.arg("plain"))) {
        rawTs = doc["timestamp"] | 0ULL;
      }
    }
    uint32_t epochSec = (rawTs > 100000000000ULL) ? (uint32_t)(rawTs / 1000ULL) : (uint32_t)rawTs;
    bool ok = false;
    if (isValidEpochSec((time_t)epochSec)) {
      struct timeval tv = { .tv_sec = (time_t)epochSec, .tv_usec = 0 };
      settimeofday(&tv, nullptr);
      if (rtcOk) rtc.adjust(DateTime(epochSec));
      ok = true;
    }
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(ok ? 200 : 400, "application/json",
                ok ? "{\"status\":\"ok\"}" : "{\"status\":\"error\",\"message\":\"Invalid timestamp\"}");
  });

  server.on("/api/schedules", HTTP_GET, []() {
    String saved = prefs.getString("schedules", "[]");
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", saved);
  });

  server.on("/api/schedules", HTTP_POST, []() {
    bool ok = false;
    if (server.hasArg("plain")) {
      ok = updateSchedulesFromJson(server.arg("plain"), true);
    }
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(ok ? 200 : 400, "application/json",
                "{\"status\":\"" + String(ok ? "ok" : "error") + "\",\"count\":" + String((unsigned)scheduleCount) + "}");
  });

  server.on("/api/logs", HTTP_GET, []() {
    String out = "[";
    for (size_t i = 0; i < localLogCount; i++) {
      size_t idx = (localLogHead + MAX_LOCAL_LOGS - 1 - i) % MAX_LOCAL_LOGS;
      if (i > 0) out += ",";
      out += localLogBuffer[idx];
    }
    out += "]";
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.send(200, "application/json", out);
  });

  // Embedded mobile web dashboard for direct in-browser access
  server.on("/", HTTP_GET, []() {
    float vbat = readBatteryVolts();
    float level = readFeedLevelPercent();
    float weight = 0.0f;
    safeReadScaleGrams(&weight, 1);

    String html = "<!DOCTYPE html><html><head><meta name='viewport' content='width=device-width,initial-scale=1'>"
      "<title>Smart Chicken Feeder</title>"
      "<style>"
      "body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;margin:0;padding:20px;background:#141716;color:#e8ede9;text-align:center}"
      ".card{background:#1e2422;border-radius:18px;padding:20px;margin-bottom:16px;border:1px solid #2e3834;box-shadow:0 4px 12px rgba(0,0,0,0.3)}"
      "h1{color:#4ade80;font-size:22px;margin-top:0}h2{font-size:14px;color:#8ba396;text-transform:uppercase;letter-spacing:1px}"
      ".val{font-size:32px;font-weight:900;font-family:monospace;margin:6px 0}"
      "button{background:#15803d;color:#fff;border:none;padding:14px 24px;border-radius:12px;font-size:16px;font-weight:bold;margin:6px 0;cursor:pointer;width:100%;max-width:320px}"
      "button.stop{background:#dc2626}button.tare{background:#0284c7}"
      "</style></head><body>"
      "<div class='card'><h1>Smart Chicken Feeder</h1><p style='color:#8ba396;font-size:12px'>Direct Local Wi-Fi Portal (192.168.4.1)</p></div>"
      "<div class='card'><h2>Hopper Feed Level</h2><div class='val' style='color:#4ade80'>" + (level >= 0.0f ? String((int)round(level)) + "%" : String("SENSOR ERR")) + "</div></div>"
      "<div class='card'><h2>Scale Weight</h2><div class='val'>" + (loadCellHealthy ? String(max(0.0f, weight), 1) + " g" : String("HX711 N/A")) + "</div></div>"
      "<div class='card'><h2>Battery Voltage</h2><div class='val' style='color:#38bdf8'>" + String(vbat, 2) + " V</div></div>"
      "<div class='card'><h2>Manual Controls</h2>"
      "<form method='POST' action='/api/dispense'><button type='submit'>Dispense Feed (5s)</button></form>"
      "<form method='POST' action='/api/tare'><button class='tare' type='submit'>Tare Scale (0.0g)</button></form>"
      "<form method='POST' action='/api/stop'><button class='stop' type='submit'>Emergency Stop</button></form>"
      "</div></body></html>";
    server.send(200, "text/html", html);
  });

  server.enableCORS(true);
  server.begin();
  Serial.printf("[HTTP] Embedded REST server listening on port %d\n", HTTP_SERVER_PORT);
}

// ---------- Wi-Fi & Firebase Realtime Database Sync ----------

void purgeStaleCommandsOnBoot() {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL)) return;
  authenticateFirebase(false);

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  if (https.begin(client, buildFirebaseUrl("commands/dispense.json"))) {
    https.setTimeout(2500);
    if (https.GET() == 200) {
      String payload = https.getString();
      if (payload.length() > 0 && payload != "null") {
        JsonDocument doc;
        if (!deserializeJson(doc, payload)) {
          String staleId = String((const char*)(doc["id"] | ""));
          const char* act = doc["action"] | "UNKNOWN";
          Serial.printf("[BOOT SAFETY] Purging pre-boot queued command %s (%s) without motor actuation.\n",
                        staleId.c_str(), act);
          https.end();
          firebaseDeletePath("commands/dispense.json");
          firebaseDeletePath("commands/stop.json");
          if (staleId.length() > 0) {
            lastExecutedCommandId = staleId;
            prefs.putString("lastCmdId", lastExecutedCommandId);
            updateCommandAckInFirebase(staleId, act, "timeout", 0.0f,
                                       "Cleared pre-boot stale command on controller startup");
          }
          return;
        }
      }
    }
    https.end();
  }
}

void initWiFi() {
  WiFi.mode(WIFI_AP_STA);
  bool apSuccess = WiFi.softAP(SOFTAP_SSID, SOFTAP_PASSWORD, SOFTAP_CHANNEL, 0, SOFTAP_MAX_CONN);
  if (apSuccess) {
    IPAddress apIP = WiFi.softAPIP();
    Serial.println("-------------------------------------------------");
    Serial.printf("[SOFTAP] Direct Wi-Fi Active: SSID='%s'\n", SOFTAP_SSID);
    Serial.printf("[SOFTAP] Access Point IP: %s\n", apIP.toString().c_str());
    Serial.println("-------------------------------------------------");
  } else {
    Serial.println("[SOFTAP ERROR] Failed to start SoftAP hotspot.");
  }

  if (isConfiguredValue(WIFI_SSID)) {
    Serial.printf("[WIFI STA] Connecting to station network '%s'...\n", WIFI_SSID);
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    unsigned long waitStart = millis();
    while (WiFi.status() != WL_CONNECTED && millis() - waitStart < 6000UL) {
      delay(200);
    }
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("[WIFI STA] Connected! IP=%s\n", WiFi.localIP().toString().c_str());
      syncNtpAndRtcIfConnected();
      authenticateFirebase(true);
      purgeStaleCommandsOnBoot();
      syncSchedulesFromFirebase();
    } else {
      Serial.println("[WIFI STA] Initial connect timed out; continuing non-blocking in background.");
    }
  } else {
    Serial.println("[WIFI STA] No station SSID set. Operating in pure direct SoftAP mode.");
  }

  setupWebServer();
}

void checkWiFiReconnect() {
  if (!isConfiguredValue(WIFI_SSID)) return;
  static bool wasConnected = false;
  bool nowConnected = (WiFi.status() == WL_CONNECTED);

  if (nowConnected && !wasConnected) {
    wasConnected = true;
    Serial.printf("[WIFI] Station link active (%s). Syncing clock, purging stale queue & syncing schedules.\n",
                  WiFi.localIP().toString().c_str());
    syncNtpAndRtcIfConnected();
    authenticateFirebase(false);
    purgeStaleCommandsOnBoot();
    syncSchedulesFromFirebase();
  } else if (!nowConnected) {
    wasConnected = false;
    static unsigned long lastCheck = 0UL;
    if (millis() - lastCheck >= WIFI_RECONNECT_INTERVAL_MS) {
      lastCheck = millis();
      Serial.println("[WIFI] Station link offline. Attempting non-blocking reconnect...");
      WiFi.reconnect();
    }
  }
}

void syncTelemetryToFirebase(const String& jsonPayload) {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL)) return;
  authenticateFirebase(false);

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  if (https.begin(client, buildFirebaseUrl("telemetry.json"))) {
    https.addHeader("Content-Type", "application/json");
    https.setTimeout(3000);
    int httpCode = https.PUT(jsonPayload);
    if (httpCode == 401 && authenticateFirebase(true)) {
      https.end();
      if (https.begin(client, buildFirebaseUrl("telemetry.json"))) {
        https.addHeader("Content-Type", "application/json");
        https.setTimeout(3000);
        httpCode = https.PUT(jsonPayload);
      }
    }
    if (httpCode <= 0) {
      Serial.printf("[CLOUD ERROR] Telemetry sync failed: %s\n", https.errorToString(httpCode).c_str());
    }
    https.end();
  }
}

void syncLogToFirebase(const String& logId, const String& jsonPayload) {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL)) return;
  authenticateFirebase(false);

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  String path = "logs/" + logId + ".json";
  if (https.begin(client, buildFirebaseUrl(path))) {
    https.addHeader("Content-Type", "application/json");
    https.setTimeout(4000);
    int httpCode = https.PUT(jsonPayload);
    if (httpCode == 401 && authenticateFirebase(true)) {
      https.end();
      if (https.begin(client, buildFirebaseUrl(path))) {
        https.addHeader("Content-Type", "application/json");
        https.setTimeout(4000);
        httpCode = https.PUT(jsonPayload);
      }
    }
    if (httpCode > 0) {
      Serial.printf("[CLOUD] Feeding log %s stored: HTTP %d\n", logId.c_str(), httpCode);
    }
    https.end();
  }
}

void pollFirebaseCommands() {
  if (WiFi.status() != WL_CONNECTED || !isConfiguredValue(FIREBASE_DB_URL) || isDispensing) return;
  authenticateFirebase(false);

  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;

  if (https.begin(client, buildFirebaseUrl("commands/dispense.json"))) {
    https.setTimeout(2500);
    int httpCode = https.GET();
    if (httpCode == 401 && authenticateFirebase(true)) {
      https.end();
      if (https.begin(client, buildFirebaseUrl("commands/dispense.json"))) {
        https.setTimeout(2500);
        httpCode = https.GET();
      }
    }
    if (httpCode == 200) {
      String payload = https.getString();
      https.end();
      if (payload.length() > 0 && payload != "null") {
        Serial.printf("[CLOUD] Received remote command: %s\n", payload.c_str());
        // Consume from queue BEFORE actuating motor so brownout/reset can never loop-dispense!
        firebaseDeletePath("commands/dispense.json");
        handleCommand(payload, true);
      }
      return;
    }
    https.end();
  }
}

void setup() {
  Serial.begin(115200);
  pinMode(PIN_US_TRIG, OUTPUT);
  pinMode(PIN_US_ECHO, INPUT);
  analogReadResolution(12);

  // Immediately close dispenser gate on boot before any network/sensor init
  gate.attach(PIN_SERVO);
  gate.write(SERVO_CLOSED_DEG);

  prefs.begin("feeder", false);
  loadPersistentStateFromNvs();

  scale.begin(PIN_HX711_DOUT, PIN_HX711_SCK);
  scale.set_scale(currentCalFactor);
  safeScaleTare(5); // Non-blocking: will not hang boot if HX711 is unplugged!

  Wire.begin(PIN_RTC_SDA, PIN_RTC_SCL);
  rtcOk = rtc.begin();
  if (rtcOk && rtc.lostPower()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  }

  Serial.println("=================================================");
  Serial.println(" Smart Chicken Feeder - Hardened Firmware v1.1   ");
  Serial.println(" Dual Mode: Direct SoftAP + Authenticated Cloud  ");
  Serial.println("=================================================");

  initWiFi();
  printTelemetryJson();
}

void loop() {
  server.handleClient();
  checkWiFiReconnect();

  // Safety auto-close if bench SERVO_TEST left gate open
  if (!isDispensing && servoTestAutoCloseAtMs > 0UL && millis() >= servoTestAutoCloseAtMs) {
    servoTestAutoCloseAtMs = 0UL;
    gate.write(SERVO_CLOSED_DEG);
    Serial.println("[SAFETY] Bench servo test auto-closed gate to 0 deg.");
  }

  static unsigned long lastTelemetry = 0UL;
  if (millis() - lastTelemetry >= TELEMETRY_INTERVAL_MS && !isDispensing) {
    lastTelemetry = millis();
    syncNtpAndRtcIfConnected();
    printTelemetryJson();
  }

  static unsigned long lastCommandPoll = 0UL;
  if (millis() - lastCommandPoll >= COMMAND_POLL_INTERVAL_MS && !isDispensing) {
    lastCommandPoll = millis();
    pollFirebaseCommands();
  }

  static unsigned long lastScheduleSync = 0UL;
  if (millis() - lastScheduleSync >= SCHEDULE_SYNC_INTERVAL_MS && !isDispensing) {
    lastScheduleSync = millis();
    syncSchedulesFromFirebase();
  }

  static unsigned long lastScheduleCheck = 0UL;
  if (millis() - lastScheduleCheck >= 5000UL && !isDispensing) {
    lastScheduleCheck = millis();
    checkAutonomousSchedules();
  }

  // Process incoming USB Serial command (JSON or single-char shortcut)
  if (Serial.available()) {
    String input = Serial.readStringUntil('\n');
    input.trim();
    if (input.length() > 0) {
      if (input.startsWith("{")) {
        handleCommand(input, false);
      } else if (input == "f") {
        dispenseFeed(DEFAULT_TARGET_GRAMS, "Manual (Serial)");
      } else if (input == "t") {
        safeScaleTare(8);
        Serial.println("[CMD] Load cell tared");
      } else if (input == "s" || input.equalsIgnoreCase("stop")) {
        emergencyStopRequested = true;
        gate.write(SERVO_CLOSED_DEG);
      }
    }
  }
}
