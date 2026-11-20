#pragma once
// Hardware pin map and system thresholds.
// Secrets (Wi-Fi / Firebase) live in secrets.h, which is git-ignored.
// Copy secrets.example.h -> secrets.h and fill in your values.

// ---------- Installed Hardware Modules ----------
#define HAS_ULTRASONIC     0    // HC-SR04 not installed by builder
#define HAS_RTC_DS3231     0    // DS3231 not installed by builder (uses ESP32 internal RTC + NTP/App sync)
#define HAS_BATTERY_ADC    0    // 12V battery voltage divider not connected to GPIO 34

// ---------- Pins (ESP32 38-Pin Yellow Header) ----------
#define PIN_SERVO          18   // DS-S020A-C 30kg dispenser gate servo (PWM) [CONNECTED]
#define PIN_HX711_DOUT     23   // load cell amplifier data (DT) [CONNECTED @ 3V3]
#define PIN_HX711_SCK      22   // load cell amplifier clock (SCK) [CONNECTED @ 3V3]
#define PIN_US_TRIG        5    // HC-SR04 trigger (unused when HAS_ULTRASONIC == 0)
#define PIN_US_ECHO        19   // HC-SR04 echo (unused when HAS_ULTRASONIC == 0)
#define PIN_BATTERY_ADC    34   // battery voltage via divider (input-only pin)
#define PIN_RTC_SDA        25   // DS3231 I2C SDA (unused when HAS_RTC_DS3231 == 0)
#define PIN_RTC_SCL        26   // DS3231 I2C SCL (unused when HAS_RTC_DS3231 == 0)

// ---------- Servo (DS-S020A-C 30kg — Center-Closed Gate Geometry) ----------
// 90 deg = Middle (orange paddle centered directly under hopper pipe = CLOSED)
// 40 deg = Open (50 deg sweep from center = OPEN; returns back to 90 deg = CLOSED)
#define SERVO_MIN_SAFE_DEG       0
#define SERVO_MAX_SAFE_DEG       180
#define SERVO_CLOSED_DEG         90
#define SERVO_OPEN_DEG           40
#define SERVO_STEP_DEG           5        // smooth ramp step to limit battery inrush
#define SERVO_STEP_DELAY_MS      14UL     // delay per step (~155ms crisp smooth ramp)
#define SERVO_CLOSE_HOLD_MS      900UL    // hold firm torque at closed seat before detaching PWM
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
#define SOFTAP_CHANNEL         11
#define SOFTAP_MAX_CONN        4
#define HTTP_SERVER_PORT       80
