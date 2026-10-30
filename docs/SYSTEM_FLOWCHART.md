# Complete System Flowcharts & Operational Workflows

**Project:** SMART MOBILE-BASED SOLAR-POWERED CHICKEN FEEDING SYSTEM WITH AUTOMATED DISPENSING AND REAL-TIME ALERTS  
**Repository:** https://github.com/Jehooooo/SMART-MOBILE-BASED-SOLAR-POWERED-CHICKEN-FEEDING-SYSTEM  
**Document Version:** 1.0.0  

---

## Table of Contents

1. [Status Classification Legend](#status-classification-legend)
2. [Flowchart 1: Overall System Architecture](#flowchart-1-overall-system-architecture)
3. [Flowchart 2: Mobile Application Workflow](#flowchart-2-mobile-application-workflow)
4. [Flowchart 3: ESP32 Firmware Boot & Main Loop Workflow](#flowchart-3-esp32-firmware-boot--main-loop-workflow)
5. [Flowchart 4: Firebase Communication & Command Lifecycle Workflow](#flowchart-4-firebase-communication--command-lifecycle-workflow)
6. [Flowchart 5: Automated Feeding Workflow (Gravimetric & Timed Fallback)](#flowchart-5-automated-feeding-workflow-gravimetric--timed-fallback)
7. [Flowchart 6: Manual Feeding & Emergency Stop Workflow](#flowchart-6-manual-feeding--emergency-stop-workflow)
8. [Flowchart 7: Scheduled Feeding Workflow (Cloud Sync & Offline RTC)](#flowchart-7-scheduled-feeding-workflow-cloud-sync--offline-rtc)
9. [Flowchart 8: Sensor Monitoring & Health Evaluation Workflow](#flowchart-8-sensor-monitoring--health-evaluation-workflow)
10. [Flowchart 9: Notification & Real-Time Alert Workflow](#flowchart-9-notification--real-time-alert-workflow)
11. [Flowchart 10: Wi-Fi Connection, SoftAP & Reconnection Workflow](#flowchart-10-wi-fi-connection-softap--reconnection-workflow)
12. [Flowchart 11: Error Handling, Safety Interlocks & Recovery Workflow](#flowchart-11-error-handling-safety-interlocks--recovery-workflow)

---

## Status Classification Legend

Every workflow node and branch in this document is verified directly against the repository source code (`firmware/src/main.cpp`, `firmware/include/config.h`, `database.rules.json`, and `app/lib/`):

| Classification | Meaning |
| :--- | :--- |
| **IMPLEMENTED** | Present and active in the repository source code (`app/` or `firmware/`). |
| **TESTED** | Verified via automated software unit/socket tests (`24/24` passed) and firmware compilation (`pio run`). |
| **NOT VERIFIED** | Code is implemented, but physical bench/field verification with live poultry feed and solar hardware is still required. |
| **NOT IMPLEMENTED** | Feature is intentionally excluded from the current system scope. |
| **RECOMMENDED IMPROVEMENT** | Optional future enhancement not present in current firmware/app code, clearly separated from existing behavior. |

---

## Flowchart 1: Overall System Architecture

This diagram illustrates the end-to-end relationship among the off-grid solar power subsystem, physical sensors and servo actuator, the ESP32-WROOM-32 dual-mode controller, the Firebase Realtime Database cloud backend (`asia-southeast1`), and the Flutter mobile/web client.

```mermaid
flowchart TD
    subgraph PowerLayer["1. Solar Power & Electrical Distribution Subsystem"]
        SP["12V Monocrystalline Solar Panel"] --> SCC["12V PWM Solar Charge Controller"]
        SCC <--> BAT["12V Rechargeable Battery (Lead-Acid / LiFePO4)"]
        BAT --> BUCK["LM2596 DC-DC Buck Converter (Tuned to 5.0V DC)"]
        BAT --> VDIV["Voltage Divider (40k Ohm / 10k Ohm -> 5.0x Ratio)"]
    end

    subgraph HardwareLayer["2. Physical Sensors & Dispensing Actuator"]
        SERVO["MG996R High-Torque Servo Gate (GPIO 13 PWM: 0 deg Closed / 90 deg Open)"]
        HX711["5kg Load Cell + HX711 24-bit ADC (DOUT GPIO 16 / SCK GPIO 17)"]
        HCSR04["HC-SR04 Ultrasonic Hopper Sensor (TRIG GPIO 5 / ECHO GPIO 18 via 3.3V Divider)"]
        DS3231["DS3231 I2C Real-Time Clock + CR2032 Backup (SDA GPIO 21 / SCL GPIO 22)"]
    end

    subgraph ControllerLayer["3. Embedded Controller (ESP32-WROOM-32 - firmware/src/main.cpp)"]
        ESP["ESP32 Microcontroller (WIFI_AP_STA Dual Mode)"]
        NVS["Onboard NVS Flash ('feeder' Namespace: calFactor, schedules, lastCmdId, lastSchSlot)"]
        AP_SRV["Embedded HTTP REST Server & Portal (SmartFeeder-AP @ 192.168.4.1:80)"]
        ESP <--> NVS
        ESP --- AP_SRV
    end

    subgraph CloudLayer["4. Cloud Backend (Firebase - asia-southeast1)"]
        FBAUTH["Firebase Authentication (Email/Password or Anonymous Sign-In)"]
        RTDB[("Firebase Realtime Database (/telemetry, /commands, /schedules, /logs)")]
        FBAUTH --> RTDB
    end

    subgraph ClientLayer["5. User Client Application (Flutter - app/lib/)"]
        ADAPTER["FeederHardwareAdapter Strategy Interface"]
        FB_ADAPT["FirebaseHardwareAdapter (Native SDK + HTTPS REST Fallback)"]
        REST_ADAPT["RestHardwareAdapter (Direct Wi-Fi HTTP @ 192.168.4.1)"]
        SVC["FeederService State Engine + SharedPreferences Offline Cache"]
        ALERTS["AlertNotificationService (Local OS Notifications + Cooldown Latch)"]
        UI["4-Tab Liquid Glass UI (Dashboard, Schedules, History & CSV, Settings & Diagnostics)"]

        UI <--> SVC
        SVC <--> ADAPTER
        SVC --> ALERTS
        ADAPTER --> FB_ADAPT
        ADAPTER --> REST_ADAPT
    end

    BUCK -- "5.0V Rail + Common GND" --> ESP
    BUCK -- "Dedicated 5.0V High-Current Rail" --> SERVO
    VDIV -- "0-3.3V Analog Sense (GPIO 34)" --> ESP
    ESP -- "PWM Control" --> SERVO
    HX711 -- "24-bit Weight Data" --> ESP
    HCSR04 -- "Echo Pulse Depth" --> ESP
    DS3231 <-->|"I2C Timekeep"| ESP

    ESP <-->|"Station Wi-Fi (HTTPS REST + Auth Token)"| RTDB
    FB_ADAPT <-->|"4G/LTE or Wi-Fi (WebSocket / HTTPS)"| RTDB
    REST_ADAPT <-->|"Direct Phone-to-ESP32 Wi-Fi (HTTP JSON)"| AP_SRV
```

---

## Flowchart 2: Mobile Application Workflow

Traces the complete lifecycle of the Flutter application from startup (`app/lib/main.dart`) through onboarding, transport initialization, dashboard monitoring, manual feeding, schedule management, log export, diagnostics, and alert handling.

```mermaid
flowchart TD
    START(["User Launches Smart Chicken Feeder App"]) --> BIND["WidgetsFlutterBinding.ensureInitialized()"]
    BIND --> INIT_PAR["Load SettingsService (SharedPreferences) & Initialize AlertNotificationService"]
    INIT_PAR --> CHECK_OB{"onboardingComplete == true?"}

    CHECK_OB -- "No (First Launch)" --> OB_SCR["Display 4-Slide OnboardingScreen ('Skip' or 'GET STARTED')"]
    OB_SCR --> SET_OB["Save onboardingComplete = true"]
    SET_OB --> INIT_FB

    CHECK_OB -- "Yes" --> INIT_FB["Initialize Firebase Core & Select Hardware Transport"]
    INIT_FB --> TRANS_SEL{"Saved HardwareTransportType?"}

    TRANS_SEL -- "firebaseCloud (Default)" --> FB_INIT["Create FirebaseHardwareAdapter (Sign In Anonymously + Bind RTDB Streams)"]
    TRANS_SEL -- "localRestHttp" --> REST_INIT["Create RestHardwareAdapter (Poll http://192.168.4.1 every 2s)"]

    FB_INIT --> HYDRATE["FeederService Hydrates Cached Telemetry, Schedules & Logs from SharedPreferences"]
    REST_INIT --> HYDRATE

    HYDRATE --> SHELL["Render MainNavigationShell (4 Bottom Tabs / Wide NavigationRail)"]

    SHELL --> TAB1["Tab 1: DashboardScreen"]
    SHELL --> TAB2["Tab 2: SchedulesScreen"]
    SHELL --> TAB3["Tab 3: HistoryScreen"]
    SHELL --> TAB4["Tab 4: SettingsScreen"]

    TAB1 --> D_VIEW["View Hopper %, Estimated kg & Supply Days, Solar Charging, Battery V/%, Next Routine"]
    D_VIEW --> D_ACT{"User Action on Dashboard?"}
    D_ACT -- "Tap Refresh / Pull Down" --> D_SYNC["feederService.refreshTelemetry()"]
    D_ACT -- "Tap (i) Info Icon" --> D_GUIDE["Open 4-Tab Machine & Backend Guide Modal"]
    D_ACT -- "Select 1-30s & Tap DISPENSE" --> D_MAN["Confirm Dialog -> triggerManualFeed() -> Live Progress & Emergency Stop"]

    TAB2 --> S_VIEW["View Active Routine Count, Daily Grams & Schedule Cards"]
    S_VIEW --> S_ACT{"User Action on Schedules?"}
    S_ACT -- "Tap + Add / Tap Card" --> S_EDIT["Validate 1-60s & Unique HH:MM -> Save to Local Cache + Cloud/REST"]
    S_ACT -- "Toggle Switch" --> S_TOG["Enable/Pause Schedule -> Sync to Feeder"]
    S_ACT -- "Tap Play Icon" --> S_TEST["Test Run Routine Immediately (triggerSchedule)"]
    S_ACT -- "Tap Delete Icon" --> S_DEL["Confirm Delete -> Remove + Show 4-Second UNDO Snackbar"]

    TAB3 --> H_VIEW["View Performance Metrics (Total Feeds, Avg Accuracy %, Total Dispensed)"]
    H_VIEW --> H_ACT{"User Action on History?"}
    H_ACT -- "Tap Filter Chip" --> H_FILT["Filter List: All / Scheduled / Manual"]
    H_ACT -- "Tap Download Icon" --> H_EXP["Open Export Modal -> Save UTF-8 BOM CSV to Downloads Folder"]

    TAB4 --> SET_VIEW["Configure Theme, Feeder Name, Hopper kg, Transport & Alert Thresholds (10-40%)"]
    SET_VIEW --> SET_DIAG["Tap 'Open Suite' -> DiagnosticsScreen (2-Point Scale Calibration, HC-SR04 Depth, Servo 0/45/90 deg)"]

    FB_INIT -. "Live Telemetry / Log Stream" .-> EVAL_ALT["AlertNotificationService Evaluates Confirmed Telemetry & New Logs"]
    REST_INIT -. "Polled Telemetry / Log Stream" .-> EVAL_ALT
    EVAL_ALT --> SHOW_ALT["Update ConnectionBanner, Warning Cards & Android/iOS Local Notification"]
```

---

## Flowchart 3: ESP32 Firmware Boot & Main Loop Workflow

Reflects the exact non-blocking execution architecture implemented in `firmware/src/main.cpp` (`setup()` lines 1353–1454 and `loop()` lines 1456–1528).

```mermaid
flowchart TD
    BOOT(["ESP32 Power-On / Reset"]) --> SERIAL["Serial.begin(115200) & Status LED (GPIO 2) LOW"]
    SERIAL --> SAFE_GATE["SAFETY FIRST: Attach Servo (GPIO 13) & Close Gate Immediately to 0 deg"]
    SAFE_GATE --> LOAD_NVS["Open NVS Preferences ('feeder'): Load calFactor, lastCmdId, lastSchSlot & Saved Schedules"]
    LOAD_NVS --> INIT_SENS["Configure Ultrasonic Pins (TRIG 5, ECHO 18), Battery ADC (GPIO 34, 11dB) & HX711 (GPIO 16/17)"]

    INIT_SENS --> CHK_HX{"HX711 Ready Within 800ms?"}
    CHK_HX -- "Yes" --> TARE_BOOT["Apply calFactor & Run safeScaleTare(10)"]
    CHK_HX -- "No" --> WARN_HX["Set hx711Ready = false & lastSensorError = 'hx711_boot_timeout'"]

    TARE_BOOT --> INIT_RTC["Wire.begin(21, 22) & Probe DS3231 I2C Real-Time Clock"]
    WARN_HX --> INIT_RTC

    INIT_RTC --> WIFI_MODE["Set WiFi.mode(WIFI_AP_STA) & Start SoftAP 'SmartFeeder-AP' (192.168.4.1:80)"]
    WIFI_MODE --> HTTP_START["Register Local REST Endpoints (/api/*) & httpServer.begin()"]
    HTTP_START --> STA_TRY{"WIFI_SSID Configured & Connected Within 6s?"}

    STA_TRY -- "Yes" --> CLOUD_BOOT["Sync NTP Clock (UTC+8) -> Update DS3231 if Lost Power -> Obtain Firebase Auth Token"]
    CLOUD_BOOT --> PURGE_BOOT["purgeStaleCommandsOnBoot() (DELETE /commands/dispense & /stop) + syncSchedulesFromFirebase()"]
    PURGE_BOOT --> PUSH_INIT["pushTelemetryToFirebase() Initial Snapshot"]
    STA_TRY -- "No (Offline / Off-Grid)" --> WARN_WIFI["Log Offline Mode: SoftAP + DS3231 Autonomous Schedules Active"]

    PUSH_INIT --> LOOP_START(["Enter Non-Blocking loop() (10ms Yield Cycle)"])
    WARN_WIFI --> LOOP_START

    LOOP_START --> L_HTTP["1. httpServer.handleClient() & handleSerialCommands()"]
    L_HTTP --> L_SERVO_AUTO{"Servo Bench Test Active & > 10s Elapsed?"}
    L_SERVO_AUTO -- "Yes" --> CLOSE_BENCH["Auto-Close Servo Gate to 0 deg"] --> L_WIFI_TMR
    L_SERVO_AUTO -- "No" --> L_WIFI_TMR{"2. Every 15,000 ms: Check Station Wi-Fi"}

    L_WIFI_TMR -- "Disconnected" --> WIFI_REC["Non-Blocking WiFi.reconnect()"] --> L_CMD_TMR
    L_WIFI_TMR -- "Just Reconnected" --> WIFI_RESYNC["Sync NTP + purgeStaleCommandsOnBoot() + syncSchedulesFromFirebase()"] --> L_CMD_TMR
    L_WIFI_TMR -- "Unchanged" --> L_CMD_TMR{"3. Every 1,500 ms (If Wi-Fi Connected): Poll Commands"}

    L_CMD_TMR -- "Due" --> POLL_FB["pollFirebaseCommands() (/commands/dispense.json)"] --> L_TELEM_TMR
    L_CMD_TMR -- "Not Due" --> L_TELEM_TMR{"4. Every 10,000 ms: Telemetry Cycle"}

    L_TELEM_TMR -- "Due" --> PUSH_TELEM["Read Sensors -> Update Status -> Push /telemetry.json (If Wi-Fi Connected)"] --> L_SCH_SYNC
    L_TELEM_TMR -- "Not Due" --> L_SCH_SYNC{"5. Every 30,000 ms (If Wi-Fi Connected): Schedule Sync"}

    L_SCH_SYNC -- "Due" --> SYNC_SCH["syncSchedulesFromFirebase() (/schedules.json -> NVS)"] --> L_AUTO_SCH
    L_SCH_SYNC -- "Not Due" --> L_AUTO_SCH{"6. Every 5,000 ms: Autonomous Schedule Check"}

    L_AUTO_SCH -- "Due" --> CHK_RTC["checkAutonomousSchedules() via DS3231 / NTP"] --> LOOP_DELAY["delay(10)"]
    L_AUTO_SCH -- "Not Due" --> LOOP_DELAY
    LOOP_DELAY --> LOOP_START
```

---

## Flowchart 4: Firebase Communication & Command Lifecycle Workflow

Shows the exact authentication, command queuing, pre-actuation deletion, execution acknowledgement, telemetry streaming, and token refresh sequence between the Flutter App, Firebase Realtime Database, and ESP32.

```mermaid
sequenceDiagram
    autonumber
    participant App as Flutter Mobile App<br/>(FirebaseHardwareAdapter)
    participant Auth as Firebase Auth<br/>(IdentityToolkit REST / SDK)
    participant RTDB as Firebase Realtime Database<br/>(asia-southeast1)
    participant ESP as ESP32 Controller<br/>(firmware/src/main.cpp)

    Note over App,ESP: Phase 1: Authentication & Session Initialization
    App->>Auth: signInAnonymously()
    Auth-->>App: Firebase User UID + ID Token
    ESP->>Auth: POST accounts:signInWithPassword or accounts:signUp (Anonymous)
    Auth-->>ESP: idToken (Refreshed every 45 min or on HTTP 401)
    ESP->>RTDB: DELETE /commands/dispense.json & /commands/stop.json (Boot Safety Purge)

    Note over App,ESP: Phase 2: Periodic Telemetry Synchronization (Every 10s Idle / 1.5s Dispensing)
    ESP->>RTDB: PUT /telemetry.json?auth=<idToken> (feedLevelPercent, batteryVolts, currentWeightGrams, lastHeartbeat...)
    RTDB-->>App: Real-time onValue Stream Event (/telemetry)
    App->>App: Verify lastHeartbeat < 3 min -> Mark Feeder "Online"

    Note over App,ESP: Phase 3: Remote Command Dispatch, Pre-Actuation Delete & Acknowledgement
    App->>RTDB: PUT /commands/dispense.json (id, action="DISPENSE", durationSeconds, targetGrams, status="pending")
    App->>RTDB: PUT /commands/latest.json (status="pending")
    ESP->>RTDB: GET /commands/dispense.json (Polled every 1.5s)
    RTDB-->>ESP: Command JSON Payload
    ESP->>ESP: Validate id != lastProcessedCommandId & age <= 60,000 ms
    ESP->>RTDB: DELETE /commands/dispense.json (Prevents replay if power resets mid-feed)
    ESP->>RTDB: PATCH /commands/latest.json (status="inProgress")
    RTDB-->>App: Stream Update -> Show "Dispensing in Progress..." Banner

    Note over ESP: Actuate Servo Gate (90 deg) -> Monitor HX711 / Timer -> Close Gate (0 deg)

    ESP->>RTDB: POST /logs.json (Immutable FeedingLog record)
    ESP->>RTDB: PUT /telemetry.json (Updated weight, hopper %, lastFedTimestamp)
    ESP->>RTDB: PATCH /commands/latest.json (status="completed" | "aborted" | "failed", actualGrams)
    RTDB-->>App: Stream Updates (/logs, /telemetry, /commands/latest)
    App->>App: Refresh Dashboard & History Screen
```

---

## Flowchart 5: Automated Feeding Workflow (Gravimetric & Timed Fallback)

Details the complete physical dispensing state machine in `firmware/src/main.cpp` (`dispenseFeed` lines 632–809 and `dispenseFeedDuration` lines 815–914), including all implemented hardware safety interlocks and failure branches.

```mermaid
flowchart TD
    TRIG(["Feeding Triggered (Autonomous Schedule or Validated Remote/Local Command)"]) --> BAT_CHK{"Battery Voltage >= 11.2V? (BATTERY_CUTOFF_VOLTS)"}

    BAT_CHK -- "No (< 11.2V)" --> FAIL_BAT["Keep Gate Closed (0 deg) | Set sensorError = 'battery_cutoff_11v2' | Emit Failed Log"]
    FAIL_BAT --> SYNC_OUT

    BAT_CHK -- "Yes" --> MODE_CHK{"Dispensing Mode Selection"}
    MODE_CHK -- "Gravimetric Mode (targetGrams > 0 & Load Cell Active)" --> TARE_PRE["Run safeScaleTare(5) Before Opening Gate"]
    MODE_CHK -- "Timed Fallback Mode (durationSeconds > 0)" --> TIMED_OPEN["Clamp Duration <= 60s | Open Servo Gate to 90 deg"]

    TARE_PRE --> TARE_OK{"HX711 Tare Succeeded?"}
    TARE_OK -- "No" --> FAIL_TARE["Keep Gate Closed (0 deg) | Set sensorError = 'hx711_tare_failed_pre_dispense' | Emit Failed Log"]
    FAIL_TARE --> SYNC_OUT

    TARE_OK -- "Yes" --> GRAV_OPEN["Set isDispensing = true | Status LED HIGH | Open Servo Gate to 90 deg"]
    GRAV_OPEN --> GRAV_LOOP["Sample HX711 Weight (Non-Blocking 250ms Timeout)"]

    GRAV_LOOP --> HX_OK{"Valid Weight Read?"}
    HX_OK -- "No (Read Error)" --> ERR_CNT{"Consecutive Read Errors >= 3?"}
    ERR_CNT -- "No" --> CHK_STOP_G
    ERR_CNT -- "Yes" --> ABORT_HX["EMERGENCY CLOSE (0 deg) | sensorError = 'hx711_mid_dispense_fault'"] --> REC_LOG

    HX_OK -- "Yes" --> WT_REACHED{"dispensedGrams >= targetGrams?"}
    WT_REACHED -- "Yes (Target Reached!)" --> SUCCESS_CLOSE["Close Servo Gate to 0 deg | Wait 250ms Settling | Read Final Weight"]
    SUCCESS_CLOSE --> MARK_OK["cycleSucceeded = true | Update lastFedGrams & lastFedTimestamp"] --> REC_LOG

    WT_REACHED -- "No" --> CHK_PROG{"dispensedGrams - lastProgressGrams >= 2.0g?"}
    CHK_PROG -- "Yes (Feed Flowing)" --> UPD_PROG["Reset Stall Timer (lastProgressMs = millis())"] --> CHK_TIMEOUT
    CHK_PROG -- "No" --> CHK_STALL{"millis() - lastProgressMs > 6,000 ms? (STALL_DETECT_MS)"}

    CHK_STALL -- "Yes (Jam or Empty Hopper!)" --> ABORT_STALL["Close Servo Gate to 0 deg | sensorError = 'dispense_flow_stall'"] --> REC_LOG
    CHK_STALL -- "No" --> CHK_TIMEOUT{"Elapsed > 30,000 ms? (DISPENSE_TIMEOUT_MS)"}

    CHK_TIMEOUT -- "Yes" --> ABORT_TO["Close Servo Gate to 0 deg | sensorError = 'dispense_timeout'"] --> REC_LOG
    CHK_TIMEOUT -- "No" --> CHK_STOP_G{"Emergency Stop Received? (Serial 's', /api/stop, or /commands/stop)"}

    CHK_STOP_G -- "Yes" --> ABORT_USR["Close Servo Gate to 0 deg | sensorError = 'user_emergency_stop'"] --> REC_LOG
    CHK_STOP_G -- "No" --> STREAM_PROG["Every 1.5s: Push Live Weight Telemetry to Firebase"] --> GRAV_LOOP

    TIMED_OPEN --> TIMED_LOOP["Run Loop Until durationSeconds Elapsed (Max 60s)"]
    TIMED_LOOP --> CHK_STOP_T{"Emergency Stop Received?"}
    CHK_STOP_T -- "Yes" --> ABORT_USR
    CHK_STOP_T -- "No" --> TIMED_DONE{"Duration Complete?"}
    TIMED_DONE -- "No" --> TIMED_LOOP
    TIMED_DONE -- "Yes" --> TIMED_CLOSE["Close Servo Gate to 0 deg | Measure Actual Weight (or Estimate ~20g/s)"] --> MARK_OK

    REC_LOG["Build FeedingLog (targetGrams, actualGrams, durationSeconds, triggerType, isSuccess, batteryVolts, feedLevelPercent)"]
    REC_LOG --> SYNC_OUT["Append to Ring Buffer + POST /logs.json + PUT /telemetry.json + PATCH /commands/latest.json"]
    SYNC_OUT --> APP_UI(["Mobile App Updates Dashboard, History & Alerts"])
```

---

## Flowchart 6: Manual Feeding & Emergency Stop Workflow

Illustrates how an operator triggers an immediate feed or emergency stop from the mobile Dashboard (`app/lib/screens/dashboard_screen.dart` & `app/lib/services/feeder_service.dart`).

```mermaid
flowchart TD
    USER(["Operator Opens Dashboard Tab"]) --> SELECT["Select Preset Chip (3s / 5s / 10s / 15s) or Drag Slider (1s - 30s)"]
    SELECT --> UI_GATES{"Pre-Flight UI Safety Checks"}

    UI_GATES -- "isDeviceOnline == false" --> BLK_OFF["Disable Button: 'Manual feeding is unavailable while the feeder is offline.'"]
    UI_GATES -- "sensorError Active" --> BLK_ERR["Disable Button: 'Dispense blocked: Hardware/sensor fault active.'"]
    UI_GATES -- "feedLevelPercent < 5%" --> BLK_EMP["Disable Button: 'Dispense blocked: Hopper is empty. Refill feed first.'"]

    UI_GATES -- "All Checks Pass" --> BTN_EN["Enable 'DISPENSE <X>s NOW' Button"]
    BTN_EN --> TAP_DISP["Operator Taps Button -> 'Confirm Manual Feed' Modal Opens"]
    TAP_DISP --> CONFIRM{"Operator Taps 'Confirm & Dispense'?"}
    CONFIRM -- "Cancel" --> SELECT

    CONFIRM -- "Confirm" --> DISPATCH["FeederService.triggerManualFeed(durationSeconds)"]
    DISPATCH --> TRANSPORT{"Active Hardware Transport?"}

    TRANSPORT -- "Firebase Cloud" --> FB_SEND["Write /commands/dispense + /commands/latest (action: DISPENSE)"]
    TRANSPORT -- "Direct Wi-Fi SoftAP" --> HTTP_SEND["POST http://192.168.4.1/api/dispense"]

    FB_SEND --> IN_PROG["UI Enters Dispensing State: Show Live Progress Bar & Red 'CANCEL / EMERGENCY STOP' Button"]
    HTTP_SEND --> IN_PROG

    IN_PROG --> WATCH{"User Taps 'EMERGENCY STOP' During Cycle?"}
    WATCH -- "Yes" --> SEND_STOP["FeederService.cancelDispensing() -> Write /commands/stop OR POST /api/stop"]
    SEND_STOP --> GATE_SHUT["ESP32 Immediately Closes Servo to 0 deg & Marks Command 'aborted'"]

    WATCH -- "No" --> WAIT_FIN["ESP32 Completes Cycle & Closes Servo to 0 deg"]
    GATE_SHUT --> DONE_UI["Dashboard Restores Idle Controls + New Record Appears in History & Logs"]
    WAIT_FIN --> DONE_UI
```

---

## Flowchart 7: Scheduled Feeding Workflow (Cloud Sync & Offline RTC)

Explains how schedules are created in the app, synchronized to Firebase or SoftAP, stored in ESP32 non-volatile flash (NVS), and executed autonomously via the DS3231 Real-Time Clock even without internet (`checkAutonomousSchedules()` in `firmware/src/main.cpp` lines 572–627).

```mermaid
flowchart TD
    OPEN_SCH(["User Opens Schedules Tab & Taps '+ Add Schedule' (or Existing Card)"]) --> INPUT["Enter Label, Pick Time (HH:MM), Set Duration (1s - 60s)"]
    INPUT --> VAL_DUR{"Duration Between 1s and 60s?"}
    VAL_DUR -- "No" --> ERR_DUR["Show Inline Error: 'Please enter a valid runtime between 1s and 60s.'"] --> INPUT

    VAL_DUR -- "Yes" --> VAL_DUP{"Another Schedule Exists at Same HH:MM?"}
    VAL_DUP -- "Yes" --> ERR_DUP["Show Inline Error: 'A schedule already exists at <Time>.'"] --> INPUT

    VAL_DUP -- "No" --> SAVE_APP["Compute targetGrams = duration * 20.0 | Save to SharedPreferences Cache"]
    SAVE_APP --> PUSH_NET{"Active Transport?"}
    PUSH_NET -- "Firebase Cloud" --> PUT_FB["Write Full Map to /schedules.json"]
    PUSH_NET -- "Direct Wi-Fi SoftAP" --> POST_AP["POST Schedule Array to http://192.168.4.1/api/schedules"]

    PUT_FB --> ESP_SYNC["ESP32 Polls /schedules.json Every 30s (syncSchedulesFromFirebase)"]
    POST_AP --> ESP_NVS["ESP32 Parses Up to 16 Schedules & Saves JSON to NVS Flash ('feeder' -> 'schedules')"]
    ESP_SYNC --> ESP_NVS

    ESP_NVS --> RTC_LOOP(["ESP32 Autonomous Timer Runs Every 5,000 ms (Works 100% Offline)"])
    RTC_LOOP --> TIME_SRC{"Time Source Available?"}
    TIME_SRC -- "DS3231 RTC Present & Valid" --> GET_RTC["Read DateTime (Year, Month, Day, Hour, Minute, DayOfWeek) from DS3231"]
    TIME_SRC -- "No DS3231" --> GET_NTP["Read ESP32 Internal Clock (getLocalTime via NTP)"]

    GET_RTC --> ITER_SCH["Check Each Schedule in activeSchedules[0..scheduleCount-1]"]
    GET_NTP --> ITER_SCH

    ITER_SCH --> MATCH{"isEnabled == true AND Today in daysOfWeek AND HH:MM == Schedule HH:MM?"}
    MATCH -- "No" --> NEXT_WAIT["Wait Next 5s Cycle"]
    MATCH -- "Yes" --> SLOT_KEY["Build Deduplication Key: '{scheduleId}_{YYYYMMDD}_{HHMM}'"]

    SLOT_KEY --> CHK_DUP_EXEC{"slotKey == lastExecutedScheduleSlot in NVS?"}
    CHK_DUP_EXEC -- "Yes (Already Ran This Minute)" --> NEXT_WAIT
    CHK_DUP_EXEC -- "No" --> LOCK_NVS["Persist lastSchSlot = slotKey to NVS BEFORE Motor Runs"]
    LOCK_NVS --> EXEC_FEED["Trigger Automated Feeding (dispenseFeed if targetGrams > 0 & HX711 Ready, else dispenseFeedDuration)"]
    EXEC_FEED --> LOG_SCHED["Record FeedingLog with triggerType = 'Schedule (<label>)'"]
```

---

## Flowchart 8: Sensor Monitoring & Health Evaluation Workflow

Details how the ESP32 samples all three physical sensing subsystems and computes the prioritized system status (`firmware/src/main.cpp` lines 253–388).

```mermaid
flowchart TD
    START_MON(["Telemetry Sampling Cycle (Every 10s Idle / 1.5s Dispensing)"]) --> US_PING["1. Ultrasonic Hopper Sensor (HC-SR04: TRIG GPIO 5, ECHO GPIO 18)"]

    US_PING --> US_3X["Send Three 10us Trigger Pulses (30ms pulseIn Timeout, 2cm - 400cm Valid Filter)"]
    US_3X --> US_VALID{"At Least 1 Valid Echo?"}
    US_VALID -- "Yes" --> US_CALC["Reset Fail Streak | Map Average Distance: 5.0cm -> 100%, 30.0cm -> 0%"]
    US_VALID -- "No" --> US_STREAK{"ultrasonicFailStreak >= 3?"}
    US_STREAK -- "Yes" --> US_ERR["Set lastSensorError = 'ultrasonic_timeout' (Retain Last Known %)"]
    US_STREAK -- "No" --> US_KEEP["Retain Last Known % Without Fault"]

    US_CALC --> HX_READ["2. Load Cell Scale (HX711: DOUT GPIO 16, SCK GPIO 17)"]
    US_ERR --> HX_READ
    US_KEEP --> HX_READ

    HX_READ --> HX_WAIT{"HX711 Ready Within 250ms?"}
    HX_WAIT -- "No" --> HX_ERR1["Set hx711Ready = false & lastSensorError = 'hx711_disconnected'"]
    HX_WAIT -- "Yes" --> HX_SANITY{"Reading Finite & Within [-500g, 10,000g]?"}
    HX_SANITY -- "No" --> HX_ERR2["Set lastSensorError = 'hx711_out_of_range'"]
    HX_SANITY -- "Yes" --> HX_CLEAN["Clamp Near-Zero Noise (|w| < 0.3g -> 0.0g) & Clear Stale HX711 Faults"]

    HX_ERR1 --> BAT_ADC["3. Solar & 12V Battery Monitor (ADC GPIO 34 via 40k/10k Divider)"]
    HX_ERR2 --> BAT_ADC
    HX_CLEAN --> BAT_ADC

    BAT_ADC --> BAT_AVG["Average 4x analogReadMilliVolts(34) * 5.0 Ratio -> batteryVolts"]
    BAT_AVG --> BAT_MAP["Map State-of-Charge: 11.2V -> 0%, 12.8V -> 100% | isSolarCharging = (batteryVolts > 12.6V)"]

    BAT_MAP --> EVAL_PRI["4. Priority Status Evaluation (evaluateSystemStatus)"]
    EVAL_PRI --> P1{"isDispensing == true?"}
    P1 -- "Yes" --> ST_DISP["status = 'dispensing'"]
    P1 -- "No" --> P2{"lastSensorError Not Empty?"}
    P2 -- "Yes" --> ST_ERR["status = 'error'"]
    P2 -- "No" --> P3{"batteryVolts <= 11.5V?"}
    P3 -- "Yes" --> ST_BAT["status = 'lowBattery'"]
    P3 -- "No" --> P4{"feedLevelPercent < 20%?"}
    P4 -- "Yes" --> ST_FEED["status = 'lowFeed'"]
    P4 -- "No" --> ST_IDLE["status = 'idle'"]
```

---

## Flowchart 9: Notification & Real-Time Alert Workflow

Shows how `AlertNotificationService` (`app/lib/services/alert_notification_service.dart`) evaluates live telemetry and feeding logs while preventing cold-start false alarms and notification spam.

```mermaid
flowchart TD
    EVENT(["New Telemetry Snapshot or FeedingLog Received in FeederService"]) --> TYPE_CHK{"Event Type?"}

    TYPE_CHK -- "Telemetry Update" --> COLD_GUARD{"lastHeartbeat != null AND telemetry.isOnline (< 3 min old)?"}
    COLD_GUARD -- "No (Cold-Start / Stale)" --> IGNORE["Suppress Alert Evaluation (Prevent Placeholder False Alarms)"]

    COLD_GUARD -- "Yes (Live Hardware Confirmed)" --> CHK_HW_ERR{"status == error OR sensorError Non-Empty?"}
    CHK_HW_ERR -- "Yes" --> FIRE_HW["Queue 'Hardware Safety Fault' (Severity: CRITICAL)"]
    CHK_HW_ERR -- "No" --> CLR_HW["Unlatch 'hardware_error'"]

    CLR_HW --> CHK_FEED{"feedLevelPercent < lowFeedThreshold (Default 20%)?"}
    CHK_FEED -- "Yes" --> FIRE_FEED["Queue 'Low Feed Hopper Warning' (Severity: WARNING)"]
    CHK_FEED -- "No (>= threshold + 2% Hysteresis)" --> CLR_FEED["Unlatch 'low_feed'"]

    FIRE_HW --> CHK_BAT{"batteryPercent < lowBatteryThreshold OR batteryVolts < 11.5V?"}
    FIRE_FEED --> CHK_BAT
    CLR_FEED --> CHK_BAT

    CHK_BAT -- "Yes" --> FIRE_BAT["Queue 'Low Solar Battery Alert' (Severity: CRITICAL)"]
    CHK_BAT -- "No (>= threshold + 2% & >= 11.7V)" --> CLR_BAT["Unlatch 'low_battery'"]

    TYPE_CHK -- "New FeedingLog" --> LOG_GUARD{"Log ID Unseen AND <= 5 Min Old AND isSuccess == false?"}
    LOG_GUARD -- "No" --> IGNORE
    LOG_GUARD -- "Yes" --> FIRE_LOG["Queue 'Feeding Cycle Incomplete' Alert (Severity: CRITICAL)"]

    FIRE_BAT --> COOLDOWN_CHK{"Category Latched Within 15-Minute Cooldown?"}
    FIRE_LOG --> DISPATCH_OS
    COOLDOWN_CHK -- "Yes" --> SUPPRESS["Skip Duplicate OS Notification"]
    COOLDOWN_CHK -- "No" --> LATCH["Latch Category & Record Timestamp"] --> DISPATCH_OS

    DISPATCH_OS["Add to In-App Alert Stream + Trigger Android/iOS High-Priority Local Notification ('feeder_safety_alerts')"]
```

---

## Flowchart 10: Wi-Fi Connection, SoftAP & Reconnection Workflow

Demonstrates the actual `WIFI_AP_STA` dual-mode networking in `firmware/src/main.cpp` and transport switching in the mobile app.

```mermaid
flowchart TD
    START_NET(["ESP32 Network Initialization (setup)"]) --> DUAL_MODE["Configure WiFi.mode(WIFI_AP_STA)"]
    DUAL_MODE --> START_AP["Launch Local Hotspot: SSID 'SmartFeeder-AP' | Password 'chickens123' | IP 192.168.4.1"]
    START_AP --> CHK_SSID{"Is WIFI_SSID Non-Empty in secrets.h?"}

    CHK_SSID -- "No" --> AP_ONLY["Operate in Pure Off-Grid SoftAP Mode (HTTP Server @ 192.168.4.1 + DS3231 RTC)"]
    CHK_SSID -- "Yes" --> STA_BEGIN["Call WiFi.begin(WIFI_SSID, WIFI_PASSWORD) & Wait Up to 6s (12 x 500ms)"]

    STA_BEGIN --> STA_OK{"WL_CONNECTED?"}
    STA_OK -- "Yes" --> SYNC_CLOUD["Sync NTP Time -> Obtain Firebase Auth Token -> Purge Stale Commands -> Sync Schedules"]
    STA_OK -- "No" --> FALLBACK_AP["Continue Boot Without Blocking (SoftAP & RTC Schedules Remain Active)"]

    SYNC_CLOUD --> MON_15S["Main Loop Monitor Every 15,000 ms"]
    FALLBACK_AP --> MON_15S

    MON_15S --> LINK_STATE{"Current WiFi.status() == WL_CONNECTED?"}
    LINK_STATE -- "Yes (Already Connected)" --> KEEP_CLOUD["Normal Cloud Telemetry (10s) & Command Polling (1.5s)"]
    LINK_STATE -- "No (Connection Dropped)" --> RECONN["Log Warning & Call Non-Blocking WiFi.reconnect()"]
    RECONN --> STILL_LOCAL["During Outage: SoftAP (192.168.4.1) & Autonomous DS3231 Schedules Keep Running"]
    STILL_LOCAL --> RECOVERED{"Next 15s Check: WL_CONNECTED Restored?"}
    RECOVERED -- "No" --> RECONN
    RECOVERED -- "Yes" --> RESYNC["Re-Sync NTP + Purge Stale Commands + Pull Latest Schedules from Firebase"] --> KEEP_CLOUD
```

---

## Flowchart 11: Error Handling, Safety Interlocks & Recovery Workflow

Summarizes how the system detects, isolates, and recovers from network, power, sensor, mechanical, and command faults, distinguishing **IMPLEMENTED** behavior from **RECOMMENDED IMPROVEMENT** items.

```mermaid
flowchart TD
    FAULT(["Abnormal Condition Detected"]) --> CAT{"Fault Category"}

    CAT -- "1. Internet / Router Down" --> F_NET["[IMPLEMENTED] ESP32 retries Wi-Fi every 15s; DS3231 schedules run locally; User can switch App to SoftAP 192.168.4.1"]
    CAT -- "2. Firebase Token Expired (HTTP 401)" --> F_AUTH["[IMPLEMENTED] ESP32 clears firebaseIdToken & requests fresh token via IdentityToolkit REST; App retries Auth"]
    CAT -- "3. ESP32 Powered Off / Unreachable" --> F_OFF["[IMPLEMENTED] App detects lastHeartbeat >= 3 min old -> Shows 'Feeder controller offline' banner & blocks Manual Feed"]
    CAT -- "4. HX711 Disconnected / Fault" --> F_HX["[IMPLEMENTED] 250ms read timeout or 3 mid-dispense errors -> Closes gate to 0 deg & sets 'hx711_mid_dispense_fault'"]
    CAT -- "5. HC-SR04 Ultrasonic Timeout" --> F_US["[IMPLEMENTED] 3 consecutive empty echo cycles -> Sets 'ultrasonic_timeout' & suppresses false Low-Feed alert"]
    CAT -- "6. Mechanical Jam / Empty Hopper Flow Stall" --> F_JAM["[IMPLEMENTED] < 2.0g weight increase over 6s (or > 30s total) -> Closes gate to 0 deg & logs 'dispense_flow_stall'"]
    CAT -- "7. Low Solar Battery (< 11.2V)" --> F_BAT["[IMPLEMENTED] Hard motor lockout prevents servo brownout; ESP32 stays alive to report 'battery_cutoff_11v2'"]
    CAT -- "8. Stale (> 60s) or Duplicate Command" --> F_CMD["[IMPLEMENTED] Boot purge deletes queued commands; > 60s old commands rejected as 'expired_stale_command'"]
    CAT -- "9. Interrupted Dispensing (Power Reset)" --> F_INT["[IMPLEMENTED] Pre-actuation DELETE prevents infinite command replay; setup() forces servo gate to 0 deg immediately"]

    F_JAM -. "Future Hardware Option" .-> REC_UNJAM["[RECOMMENDED IMPROVEMENT] Automatic servo dither / reverse oscillation before locking out on stall"]
    F_NET -. "Future Firmware Option" .-> REC_LOGBUF["[RECOMMENDED IMPROVEMENT] Persist offline feeding logs to SPIFFS/LittleFS queue for delayed Firebase upload"]
```
