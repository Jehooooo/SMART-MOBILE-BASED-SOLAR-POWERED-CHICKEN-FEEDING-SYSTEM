// Smart Mobile-Based Solar-Powered Chicken Feeding System
// ESP32 firmware - hardware bring-up skeleton.
//
// Flow (per Methodology, Fig. 1):
//   RTC schedule hit -> open servo -> read load cell (HX711) until target grams
//   -> close servo -> report "feeding completed".
//   Ultrasonic sensor monitors hopper level -> low-feed alert.
//   Battery ADC monitors 12V pack -> low-battery alert.
//   Telemetry/alerts are pushed to Firebase RTDB for the Flutter app (TODO).

#include <Arduino.h>
#include <Wire.h>
#include <ESP32Servo.h>
#include <HX711.h>
#include <RTClib.h>
#include "config.h"

Servo gate;
HX711 scale;
RTC_DS3231 rtc;

static bool rtcOk = false;

float readFeedLevelPercent() {
  digitalWrite(PIN_US_TRIG, LOW);
  delayMicroseconds(2);
  digitalWrite(PIN_US_TRIG, HIGH);
  delayMicroseconds(10);
  digitalWrite(PIN_US_TRIG, LOW);
  unsigned long us = pulseIn(PIN_US_ECHO, HIGH, 30000UL);
  if (us == 0) return -1;  // sensor error / out of range
  float cm = us * 0.0343f / 2.0f;
  float pct = (HOPPER_EMPTY_CM - cm) / (HOPPER_EMPTY_CM - HOPPER_FULL_CM) * 100.0f;
  return constrain(pct, 0.0f, 100.0f);
}

float readBatteryVolts() {
  return analogReadMilliVolts(PIN_BATTERY_ADC) / 1000.0f * BATTERY_DIVIDER_RATIO;
}

// Closed-loop dispensing: keep the gate open until the load cell reaches target.
bool dispenseFeed(float targetGrams) {
  scale.tare();
  gate.write(SERVO_OPEN_DEG);
  unsigned long start = millis();
  float grams = 0;
  while (grams < targetGrams) {
    if (millis() - start > DISPENSE_TIMEOUT_MS) {
      gate.write(SERVO_CLOSED_DEG);
      Serial.printf("[ERROR] Dispense timeout at %.1f g\n", grams);
      return false;
    }
    grams = scale.get_units(3);
  }
  gate.write(SERVO_CLOSED_DEG);
  Serial.printf("[OK] Dispensed %.1f g in %lu ms\n", grams, millis() - start);
  return true;
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
  if (rtcOk && rtc.lostPower()) rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));

  Serial.println("Smart Chicken Feeder - bring-up ready. Send 'f' to test dispense.");
}

void loop() {
  static unsigned long lastTelemetry = 0;
  if (millis() - lastTelemetry >= TELEMETRY_INTERVAL_MS) {
    lastTelemetry = millis();
    float level = readFeedLevelPercent();
    float vbat = readBatteryVolts();
    DateTime now = rtcOk ? rtc.now() : DateTime((uint32_t)0);
    Serial.printf("[%02d:%02d:%02d] feed=%.0f%% battery=%.2fV weight=%.1fg\n",
                  now.hour(), now.minute(), now.second(), level, vbat,
                  scale.get_units(3));
    if (level >= 0 && level < LOW_FEED_PERCENT) Serial.println("[ALERT] Low feed level");
    if (vbat < BATTERY_LOW_VOLTS) Serial.println("[ALERT] Low battery");
  }

  if (Serial.available() && Serial.read() == 'f') {
    dispenseFeed(DEFAULT_TARGET_GRAMS);
  }
}
