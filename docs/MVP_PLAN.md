# Lean MVP & Pre-Defense Integration Plan

**Project:** Smart Mobile-Based Solar-Powered Chicken Feeding System with Automated Dispensing and Real-Time Alert  
**Last Updated:** 2026-10-30  
**Current Phase:** Software & Firmware Complete (`Testing`) → Physical Machine Bench Commissioning

---

## 1. Lean MVP Goal

Deliver a **rock-solid, defense-ready automated solar chicken feeder** that executes the complete loop reliably both online and completely off-grid:

1. **Sense:** Measure hopper feed supply (`HC-SR04`), tray weight (`HX711` + 5 kg load cell), and 12V solar/battery voltage (`GPIO 34` ADC divider) every `10s`.
2. **Schedule & Trigger:** Execute recurring daily feedings autonomously via onboard `DS3231` RTC + NVS storage, or on-demand from the Flutter Android app.
3. **Dispense Safely:** Actuate the `MG996R` gate (`0° → 90° → 0°`) until target weight (`g`) is reached (with automatic timed-duration fallback, `11.2V` brownout lockout, `6s` jam/stall cutoff, and `30s` hard timeout).
4. **Alert & Prove:** Trigger instant local OS alerts (`< 20%` hopper, `< 11.5V` battery, mechanical stall/sensor error) and export empirical accuracy trials (`Target g`, `Actual g`, `Error %`, `Battery V`) to `.xlsx` for Chapter IV thesis defense.
5. **Survive Venue Wi-Fi Drops:** Switch seamlessly in two taps between **Firebase Cloud Mode** and **Direct Local Wi-Fi (`SmartFeeder-AP` @ `http://192.168.4.1`)**.

---

## 2. MVP Scope Matrix (Anti-Bloat Guardrails)

| Capability | MVP Status | Rationale |
|:---|:---|:---|
| **Gravimetric + Timed Dispensing (`HX711` + `MG996R`)** | **In Scope (Done — Software/FW)** | Core thesis objective; timed fallback keeps machine operational even if scale needs recalibration. |
| **Hopper Level (`HC-SR04`) + 12V Solar/Battery Telemetry** | **In Scope (Done — Software/FW)** | Required for real-time monitoring, supply-days estimation, and `11.2V` brownout protection. |
| **Dual-Mode Connectivity (Firebase RTDB + SoftAP `192.168.4.1`)** | **In Scope (Done)** | Eliminates single-point failure if defense-venue internet or hotspot drops. |
| **Autonomous Offline Schedules (`DS3231` RTC + NVS)** | **In Scope (Done)** | Ensures chickens are fed on time without internet; `lastRunMinuteKey` prevents double-feeding on reboot. |
| **Local OS Threshold & Fault Notifications** | **In Scope (Done)** | `flutter_local_notifications` fires immediately on live telemetry breaches with zero paid backend cost. |
| **2-Point Load Cell Calibration & Servo Bench Wizard** | **In Scope (Done)** | Accessible via **Settings → Hardware Calibration** (`0.0g` Tare + `500g` Reference + `0°/45°/90°` gate sweep). |
| **Empirical History Charts & `.xlsx` Thesis Export** | **In Scope (Done)** | Generates Chapter IV accuracy & error-percentage datasets directly from trial runs. |
| **Paid Cloud Functions / Remote FCM Push Server** | **Out of Scope (Deferred)** | Unnecessary complexity/billing dependency before defense; local notifications cover active monitoring. |
| **Multi-Farm SaaS / Multi-Tenant RBAC** | **Out of Scope (Deferred)** | Single-feeder operator auth (`Firebase Auth` Email/Password + Anonymous device fallback) is cleaner and safer. |
| **ESP32 Deep-Sleep Duty Cycling** | **Out of Scope (Deferred)** | Keeping `WIFI_AP_STA` awake guarantees instant manual dispense response during live defense. |
| **Camera / Computer Vision / BLE GATT** | **Out of Scope (Deferred)** | Preserves deterministic ESP32 memory headroom (`15.3%` RAM, `53.4%` Flash). |

---

## 3. Verified Software & Firmware Baseline

| Subsystem | Verification Check | Status |
|:---|:---|:---|
| **Flutter Static Analysis** | `cd app; dart analyze lib/ test/` | **PASS (`0` issues)** |
| **Automated Test Suite** | `cd app; flutter test --no-pub --timeout 30s` | **PASS (`24/24` tests)** |
| **Android Build** | `cd app; flutter build apk --debug` | **PASS (`app-debug.apk` built)** |
| **ESP32 Firmware Build** | `cd firmware; pio run` | **PASS (RAM `15.3%`, Flash `53.4%`)** |
| **Firebase RTDB Rules** | `database.rules.json` (`auth != null` + command payload bounds) | **READY TO DEPLOY** |
| **Physical Hardware Trials** | Multimeter `5.0V` check, ESP32 flash, `500g` calibration, feed drop trials | **NEXT UP (Bench Commissioning)** |

---

## 4. Verified Hardware Pinout (`firmware/include/config.h`)

> [!CAUTION]
> **Tune the LM2596 buck converter to `5.00V ± 0.05V` with a multimeter BEFORE connecting the ESP32 or MG996R servo.** Power the servo from the LM2596 `5.0V` rail (never from ESP32 `3.3V`/`VIN`), with all `GND` lines tied together.

| Component | Signal | ESP32 Pin | Notes / Protection |
|:---|:---|:---|:---|
| **MG996R Servo Gate** | PWM | `GPIO 13` | `0°` closed, `90°` open; external `5.0V` LM2596 rail |
| **HX711 Load Cell Amp** | `DOUT` / `SCK` | `GPIO 16` / `GPIO 17` | `3.3V` logic; non-blocking `250ms` ready timeout |
| **HC-SR04 Ultrasonic** | `TRIG` / `ECHO` | `GPIO 5` / `GPIO 18` | `5 cm` full, `30 cm` empty; **use `5V → 3.3V` divider on `ECHO` (`GPIO 18`)** |
| **DS3231 I2C RTC** | `SDA` / `SCL` | `GPIO 21` / `GPIO 22` | `3.3V` + CR2032 backup cell |
| **12V Battery Sense** | ADC1 | `GPIO 34` | `40kΩ / 10kΩ` (`5.0x`) voltage divider; `11.2V` motor lockout |

---

## 5. Step-by-Step Physical Commissioning & Defense Runbook

### Step 1 — Power Rail Verification (5 mins)
- [ ] Disconnect ESP32 and MG996R servo from the LM2596 output.
- [ ] Connect the 12V solar battery to the LM2596 input and adjust the trim pot until a multimeter reads **`5.00V DC`**.
- [ ] Verify common `GND` continuity across battery `-`, LM2596 `GND`, ESP32 `GND`, and servo `GND`.

### Step 2 — Firebase Auth & Security Rules Activation (5 mins)
- [ ] In Firebase Console (`smart-chicken-feeder-33bec` → **Authentication → Sign-in method**), enable **Email/Password** and **Anonymous**.
- [ ] Deploy [`database.rules.json`](../database.rules.json) under **Realtime Database → Rules** (or via `firebase deploy --only database`).

### Step 3 — Flash ESP32 Firmware & Confirm Boot Health (10 mins)
- [ ] Copy `firmware/include/secrets.example.h` → `firmware/include/secrets.h` (git-ignored) and fill in `WIFI_SSID`, `WIFI_PASSWORD`, `FIREBASE_API_KEY`, and `FIREBASE_DB_URL`.
- [ ] Flash and open serial monitor:
  ```powershell
  cd firmware
  pio run -t upload
  pio device monitor -b 115200
  ```
- [ ] Confirm serial output shows:
  - Gate closed at `0°` on startup
  - `[SOFTAP] Direct Wi-Fi Active: SSID='SmartFeeder-AP'` (`192.168.4.1`)
  - `[AUTH] Firebase ID token acquired.` (when station Wi-Fi is active)
  - `TELEMETRY:{...}` JSON emitted every `10s` with valid Unix `lastHeartbeat`

### Step 4 — 2-Point HX711 Scale Calibration & Gate Sweep (10 mins)
- [ ] Install `app/build/app/outputs/flutter-apk/app-debug.apk` on Android phone (or run `flutter run`).
- [ ] Open **Settings → Hardware Calibration**:
  1. Empty the feed tray and tap **Step 1: Tare Scale (`0.0g`)**.
  2. Place a known **`500g`** calibration weight on the tray and tap **Step 2: Calibrate (`500g`)** (persists `calFactor` in ESP32 NVS).
  3. Test **`45°` Half** and **`0°` Close** to confirm smooth gate motion without binding (auto-closes after `10s` as a safety fallback).

### Step 5 — Defense Rehearsal & Empirical `.xlsx` Export (15 mins)
- [ ] **Manual & Scheduled Trial:** Run `3` manual dispenses (`100g`, `150g`, `200g`) and `1` scheduled feeding (`+2 min` from current time); verify `actualGrams` error is within target tolerance (`±5%`).
- [ ] **Safety Interlock Check:** Trigger a dispense and tap **STOP DISPENSING** mid-cycle — confirm immediate `0°` gate closure and `failed/cancelled` acknowledgment.
- [ ] **Off-Grid Fallback Rehearsal:** Turn off venue/router Wi-Fi → connect phone Wi-Fi to **`SmartFeeder-AP`** → switch app **Settings → Connection Mode → Direct Wi-Fi (`192.168.4.1`)** → confirm live telemetry and manual dispense still work instantaneously.
- [ ] **Thesis Chapter IV Export:** Open **History & Logs → Export Excel (`.xlsx`)** and save the empirical trial sheet.

---

## Production Cleanup & Mock Removal Milestone (Completed Oct 30, 2026)

- [x] **Live Firebase RTDB Sanitized:** Backed up and pruned stale development nodes (`/logs.json`, `/commands.json`, `/feeders.json`, `/telemetry.json`, `sch_1/2/3`). Verified live cloud state retains only real user routine (`sch_1792859304899`, 00:29, 100g).
- [x] **Zero Mock/Simulation Code in Production App:** Removed in-app simulator toggles, bottom sheets, simulated motor jam/sensor error switches, and fake BLE options. Production app strictly operates on **Firebase Cloud** and **Direct Wi-Fi SoftAP (`192.168.4.1`)**.
- [x] **Automated Test Decoupling:** Relocated `MockHardwareAdapter` to `app/test/mocks/` for test-only harnesses; all 24 automated unit and integration tests passing (`flutter test --no-pub`).
- [x] **Clean Initial State Preserved:** Removed `_initSampleData()` bug in `FeederService` to prevent dummy records from resurrecting on empty cloud databases.
- [x] **Firmware Build Health:** Confirmed `firmware/src/main.cpp` compiles cleanly (`pio run`) utilizing only 15.3% RAM and 53.4% Flash.


