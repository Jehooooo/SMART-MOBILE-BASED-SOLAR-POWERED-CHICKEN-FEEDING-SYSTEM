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
#define PIN_RTC_SDA        21   // DS3231 I2C SDA
#define PIN_RTC_SCL        22   // DS3231 I2C SCL

// ---------- Servo ----------
#define SERVO_CLOSED_DEG   0
#define SERVO_OPEN_DEG     90
#define SERVO_TEST_AUTO_CLOSE_MS 10000UL  // safety auto-close after bench angle test

// ---------- Dispensing & Safety Interlocks ----------
#define DEFAULT_TARGET_GRAMS       200.0f
#define MAX_DISPENSE_GRAMS         2000.0f
#define MAX_DISPENSE_DURATION_SEC  60
#define DISPENSE_TIMEOUT_MS        30000UL  // hard cutoff if target not reached
#define DISPENSE_STALL_TIMEOUT_MS  6000UL   // cutoff if weight gain <2g after 6s (jam/empty/scale fault)
#define MIN_FLOW_PROGRESS_GRAMS    2.0f
#define HX711_READY_TIMEOUT_MS     250UL    // non-blocking HX711 wait timeout
#define LOADCELL_CAL_FACTOR        420.0f   // default factor (overridden by NVS calibration)

// ---------- Feed level (hopper) ----------
#define HOPPER_EMPTY_CM    30.0f   // sensor-to-bottom distance
#define HOPPER_FULL_CM     5.0f    // sensor-to-feed distance when full
#define LOW_FEED_PERCENT   20      // alert threshold

// ---------- Battery (12V SLA / LiFePO4 pack) ----------
#define BATTERY_DIVIDER_RATIO  5.0f   // 40k/10k divider
#define BATTERY_CUTOFF_VOLTS   11.2f  // hard hardware interlock (blocks motor actuation)
#define BATTERY_LOW_VOLTS      11.5f  // low-battery telemetry warning threshold

// ---------- Time / NTP / RTC ----------
#define NTP_SERVER_1           "pool.ntp.org"
#define NTP_SERVER_2           "time.google.com"
#define GMT_OFFSET_SEC         (8L * 3600L)  // UTC+8 (Philippines Standard Time)
#define DAYLIGHT_OFFSET_SEC    0

// ---------- Telemetry, Command & Schedule Sync ----------
#define TELEMETRY_INTERVAL_MS      10000UL
#define WIFI_RECONNECT_INTERVAL_MS 15000UL
#define COMMAND_POLL_INTERVAL_MS   1500UL
#define SCHEDULE_SYNC_INTERVAL_MS  30000UL
#define COMMAND_MAX_AGE_MS         60000UL   // reject stale queued commands older than 60s
#define AUTH_REFRESH_INTERVAL_MS   2700000UL // refresh Firebase ID token every 45 min

// ---------- Direct Wi-Fi / SoftAP Mode (Off-Grid Direct Connect) ----------
#define SOFTAP_SSID            "SmartFeeder-AP"
#define SOFTAP_PASSWORD        "chickens123"   // Minimum 8 chars for WPA2
#define SOFTAP_CHANNEL         1
#define SOFTAP_MAX_CONN        4
#define HTTP_SERVER_PORT       80
