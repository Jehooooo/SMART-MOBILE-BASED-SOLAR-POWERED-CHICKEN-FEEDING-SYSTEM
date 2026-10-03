#pragma once
// Hardware pin map and system thresholds.
// Secrets (Wi-Fi / Firebase) live in secrets.h, which is git-ignored.
// Copy secrets.example.h -> secrets.h and fill in your values.

// ---------- Pins (ESP32 DevKit V1) ----------
#define PIN_SERVO          13   // dispenser gate servo (PWM)
#define PIN_HX711_DOUT     16   // load cell amplifier data
#define PIN_HX711_SCK      17   // load cell amplifier clock
#define PIN_US_TRIG        5    // HC-SR04 trigger
#define PIN_US_ECHO        18   // HC-SR04 echo (use 5V->3.3V divider!)
#define PIN_BATTERY_ADC    34   // battery voltage via divider (input-only pin)
// DS3231 RTC uses default I2C: SDA=21, SCL=22

// ---------- Servo ----------
#define SERVO_CLOSED_DEG   0
#define SERVO_OPEN_DEG     90

// ---------- Dispensing ----------
#define DEFAULT_TARGET_GRAMS   200.0f
#define DISPENSE_TIMEOUT_MS    30000UL   // raise "system error" if target not reached
#define LOADCELL_CAL_FACTOR    420.0f    // calibrate with a known weight

// ---------- Feed level (hopper) ----------
#define HOPPER_EMPTY_CM    30.0f   // sensor-to-bottom distance
#define HOPPER_FULL_CM     5.0f    // sensor-to-feed distance when full
#define LOW_FEED_PERCENT   20      // alert threshold

// ---------- Battery (12V SLA / Li-ion pack) ----------
#define BATTERY_DIVIDER_RATIO  5.0f   // e.g. 40k/10k divider
#define BATTERY_LOW_VOLTS      11.5f

// ---------- Telemetry ----------
#define TELEMETRY_INTERVAL_MS  10000UL
