# Hardware Integration Specification & Data Contract
**Project:** Smart Mobile-Based Solar-Powered Chicken Feeding System with Automated Dispensing and Real-Time Alerts  
**Target Hardware Controller:** ESP32 DevKit V1 (Tensilica Xtensa Dual-Core 32-bit LX6)  
**Target Mobile Application:** Flutter (Cross-Platform iOS / Android / Web)  
**Version:** 1.0.0 (Integration-Ready Release)  
**Document Status:** Approved Data Contract for Hardware Prototyping  

---

> [!IMPORTANT]
> **Engineering Readiness Notice:**
> The mobile application is **integration-ready** with a decoupled Hardware Integration Layer (`FeederHardwareAdapter`). While all mobile features, state machines, offline fallbacks, and error handlers have been validated using the high-fidelity `MockHardwareAdapter`, **the application must not be claimed as 100% physically compatible until physical bench testing and end-to-end dispensing with the fabricated machine have been successfully completed.** The goal of this architecture is to minimize code modifications during physical bring-up.

---

## 1. System Architecture & Hardware Pinout

The physical feeding machine operates off-grid using a 12V solar power subsystem, controlled by an ESP32 microcontroller. The software layer communicates with the hardware via an abstract transport adapter.

```
       +-------------------------------------------------------------+
       |                       FLUTTER APP                           |
       |  (UI Screens, Nielsen Feedback, Offline Banners, Settings)  |
       +-------------------------------------------------------------+
                                      |
                     [FeederHardwareAdapter Interface]
                                      |
          +---------------------------+---------------------------+
          |                           |                           |
   [Mock Simulator]           [Firebase RTDB]             [Local Wi-Fi HTTP]
   (Off-grid Emulation)    (Cloud ESP32 Stream)        (Direct ESP32 SoftAP)
          |                           |                           |
   (Software Math)                    \---------------------------/
                                                    |
                                      +---------------------------+
                                      |     ESP32 CONTROLLER      |
                                      +---------------------------+
                                        |      |       |       |
                         +--------------+      |       |       +---------------+
                         |                     |       |                       |
                    [MG996R Servo]         [HX711]  [HC-SR04]             [DS3231 RTC]
                     Dispense Gate        Load Cell  Ultrasonic           I2C Real-Time
                     (PWM GPIO 13)       (GPIO 16/17) (GPIO 5/18)           (GPIO 21/22)
```

### Microcontroller Pin Mapping (ESP32 DevKit V1)

| Subsystem | Component | ESP32 GPIO | Electrical Specs / Signal Type | Notes |
|---|---|---|---|---|
| **Dispenser Actuator** | MG996R High-Torque Servo | `GPIO 13` | PWM (50 Hz), 5V external VCC | Closed-loop gate (`0°` = closed, `90°` = open) |
| **Weighing Scale** | HX711 24-Bit ADC + Load Cell | `GPIO 16` (DOUT)<br>`GPIO 17` (SCK) | Digital 2-wire serial, 3.3V logic | Weighs dispensed grain in feed trough (target $\pm 1.5$g error) |
| **Hopper Feed Level** | HC-SR04 Ultrasonic Sensor | `GPIO 5` (TRIG)<br>`GPIO 18` (ECHO) | TTL Pulse, 5V VCC | **ECHO pin requires 5V $\to$ 3.3V resistor divider** before ESP32 |
| **Real-Time Clock** | DS3231 RTC Module | `GPIO 21` (SDA)<br>`GPIO 22` (SCL) | I2C Protocol, 3.3V | Keeps accurate schedules during off-grid solar recharge drops |
| **Solar Battery Monitor** | Voltage Divider into ADC | `GPIO 34` | Analog ADC (0–3.3V range) | $40\text{k}\Omega / 10\text{k}\Omega$ divider from 12V SLA/LiFePO4 battery pack |

---

## 2. Communication Protocols & Data Contracts

The mobile app supports three communication transports without any code changes to UI or business logic:
1. **Mock Simulator (`mockSimulator`)**: Operates entirely in memory; simulates servo physics, scale ramp-up, battery decay, and motor jam faults.
2. **Firebase Cloud Realtime Database (`firebaseCloud`)**: Uses Firebase WebSockets / REST for remote farm monitoring across 4G/LTE or farm Wi-Fi.
3. **Local Wi-Fi SoftAP REST API (`localRestHttp`)**: ESP32 broadcasts a local SSID `PoultryFeeder-AP` with an embedded HTTP webserver at `http://192.168.4.1` for zero-internet environments.

---

### Contract A: Telemetry Stream (`/telemetry`)
Emitted periodically by the ESP32 (default: every 10 seconds, or immediately upon state change).

#### JSON Schema
```json
{
  "feedLevelPercent": 78.5,
  "batteryVolts": 12.64,
  "batteryPercent": 88,
  "currentWeightGrams": 0.0,
  "status": "idle",
  "lastHeartbeat": 1776182400000,
  "lastFedTimestamp": 1776171600000,
  "lastFedGrams": 150.0,
  "isSolarCharging": true
}
```

#### Field Specifications
| Field | Type | Unit / Range | Description |
|---|---|---|---|
| `feedLevelPercent` | Float | `0.0` to `100.0` % | Calculated from HC-SR04 distance: $((\text{EmptyCm} - \text{DepthCm}) / (\text{EmptyCm} - \text{FullCm})) \times 100$ |
| `batteryVolts` | Float | `10.5` to `14.4` V | Actual 12V battery terminal voltage measured via GPIO 34 divider |
| `batteryPercent` | Integer | `0` to `100` % | State of charge (SOC): $((V - 11.2) / (12.8 - 11.2)) \times 100$ |
| `currentWeightGrams` | Float | $\ge 0.0$ grams | Instantaneous load cell weight on the feeding trough |
| `status` | String | Enum string | Valid values: `"idle"`, `"dispensing"`, `"lowFeed"`, `"lowBattery"`, `"offline"`, `"error"` |
| `lastHeartbeat` | Integer | Milliseconds Unix Epoch | Heartbeat timestamp. If `now - lastHeartbeat > 180000ms` (3 min), app flags **Offline** |
| `lastFedTimestamp` | Integer | Milliseconds Unix Epoch | Timestamp when previous feeding cycle completed |
| `lastFedGrams` | Float | grams | Quantity of feed delivered in previous feeding cycle |
| `isSolarCharging` | Boolean | `true` / `false` | True if solar panel terminal voltage exceeds battery voltage |

---

### Contract B: Machine Command Ingestion (`/commands`)
Sent by mobile app to trigger manual actions, emergency shutdown, or scale calibration.

#### Command Schema
```json
{
  "id": "cmd_1776182410000",
  "action": "DISPENSE",
  "targetGrams": 180.0,
  "timestamp": 1776182410000,
  "status": "pending",
  "errorMessage": null
}
```

#### Supported Actions
| Action String | Parameters | ESP32 Hardware Behavior |
|---|---|---|
| `DISPENSE` | `targetGrams: double` | Tares scale $\to$ writes `SERVO_OPEN_DEG` $\to$ monitors load cell until $\ge \text{targetGrams}$ $\to$ writes `SERVO_CLOSED_DEG` $\to$ logs event. |
| `EMERGENCY_STOP` | None | Immediately writes `SERVO_CLOSED_DEG` (`0°`) to halt auger/gate. Cancels active timer. |
| `TARE_SCALE` | None | Invokes `scale.tare()` on the HX711 to zero the feed trough weight. |
| `CALIBRATE_SCALE` | None | Runs tare and adjusts `LOADCELL_CAL_FACTOR` against a known reference weight. |
| `SYNC_CLOCK` | None | Sets the DS3231 RTC module registers to the provided Unix timestamp. |
| `RESTART` | None | Invokes `ESP.restart()` software reset. |

#### Command Lifecycle State Machine
```
[PENDING]  --->  (ESP32 receives command)  --->  [IN_PROGRESS]
                                                       |
                        +------------------------------+------------------------------+
                        |                                                             |
               (Target weight reached)                                       (Timeout / Error / Stop)
                        |                                                             |
                        v                                                             v
                  [COMPLETED]                                                [FAILED / ABORTED]
        (App records FeedingLog)                                    (App triggers warning banner)
```

---

### Contract C: Schedule Synchronization (`/schedules`)
Synchronized from the mobile app so that the ESP32 and DS3231 RTC execute feeding routines independently even during complete Wi-Fi or phone disconnect.

#### JSON Array Schema
```json
[
  {
    "id": "sch_1",
    "label": "Morning Feeding",
    "hour": 6,
    "minute": 30,
    "targetGrams": 180.0,
    "isEnabled": true
  },
  {
    "id": "sch_2",
    "label": "Midday Feeding",
    "hour": 12,
    "minute": 0,
    "targetGrams": 150.0,
    "isEnabled": true
  },
  {
    "id": "sch_3",
    "label": "Afternoon Feeding",
    "hour": 17,
    "minute": 30,
    "targetGrams": 200.0,
    "isEnabled": true
  }
]
```

---

### Contract D: Feeding Activity Logs (`/logs`)
Written by ESP32 upon completion of any scheduled or manual feeding cycle.

#### JSON Schema
```json
{
  "id": "log_1776182412000",
  "timestamp": 1776182412000,
  "targetGrams": 180.0,
  "actualGrams": 181.4,
  "durationSeconds": 12,
  "triggerType": "Manual",
  "isSuccess": true,
  "batteryVolts": 12.62,
  "feedLevelPercent": 76.5
}
```

---

## 3. REST API Endpoint Specifications (For Local Wi-Fi Mode)

When the machine builder uses direct Wi-Fi SoftAP (`http://192.168.4.1`):

| Method | Endpoint | Description | Request Body | Response Body |
|---|---|---|---|---|
| `GET` | `/api/telemetry` | Polls current status | None | Telemetry JSON Object |
| `POST` | `/api/dispense` | Triggers manual dispensing | `{"targetGrams": 150.0}` | `{"success": true, "status": "dispensing"}` |
| `POST` | `/api/stop` | Emergency abort | None | `{"success": true, "status": "idle"}` |
| `POST` | `/api/tare` | Tares load cell | None | `{"success": true, "weight": 0.0}` |
| `POST` | `/api/schedules` | Updates stored schedules | Array of Schedule Objects | `{"success": true, "count": 3}` |
| `GET` | `/api/logs` | Fetches historical log buffer | None | Array of Log Objects |

---

## 4. Hardware Safety & Fault Handling Rules

1. **Mechanical Jam & 30-Second Cutoff**:  
   If the dispenser gate is opened and the load cell does not reach the target grams within 30 seconds (`DISPENSE_TIMEOUT_MS = 30000UL`), the gate **MUST immediately close to 0°**, status must change to `"error"`, and an alert logged.
2. **Low Battery Hardware Interlock**:  
   If battery voltage drops below `11.2V`, dispensing operations must be blocked to prevent MCU brownout or battery damage.
3. **Ultrasonic Sensor Error / Hopper Depth**:  
   If the ultrasonic sensor returns `0` (echo loss or obstruction), the system must fallback to the last valid reading and report sensor warning without crashing.
4. **Load Cell Tare Before Dispensing**:  
   Every dispensing cycle must execute `scale.tare()` with the gate closed to establish clean zero-weight baseline, preventing cumulative error from leftover dust or droppings in the trough.

---

## 5. Physical Integration Testing Checklist

Before deploying the combined system to the poultry coop, the machine builder and software team must execute and sign off on this verification matrix:

```
[ ] STAGE 1: POWER & ELECTRICAL SAFETY
    [ ] Solar panel generates > 14V in sunlight; charge controller regulates 12V SLA battery.
    [ ] Step-down buck converter delivers stable 5.0V to servo and sensors; 3.3V to ESP32.
    [ ] HC-SR04 Echo pin voltage divider confirmed at <= 3.3V to protect ESP32 GPIO 18.
    [ ] Battery voltage divider on GPIO 34 measures 12.0V battery as ~2.4V at MCU pin.

[ ] STAGE 2: SENSOR BENCH CALIBRATION
    [ ] DS3231 RTC keeps time across battery disconnect and syncs with app via SYNC_CLOCK.
    [ ] HX711 calibrated with a known 200g test weight (LOADCELL_CAL_FACTOR adjusted).
    [ ] Weight reading tare confirmed at 0.0g +/- 0.5g with empty trough.
    [ ] HC-SR04 reads 30cm when empty (0%), 5cm when full (100%), and 18cm as ~50%.

[ ] STAGE 3: ACTUATOR GATE OPERATION
    [ ] MG996R servo moves smoothly to 0° (fully sealed) without grain dribble.
    [ ] Servo rotates cleanly to 90° upon DISPENSE command and returns promptly.
    [ ] EMERGENCY_STOP command cuts servo immediately (< 300ms) mid-dispense.

[ ] STAGE 4: TRANSPORT & CONNECTIVITY
    [ ] App connects in Mock Mode to verify UI, navigation, and settings sliders.
    [ ] App switches to Firebase Mode (or Local REST) without restart.
    [ ] Simulated offline mode banner drops down; manual feed button disables automatically.
    [ ] App reconnects smoothly when Wi-Fi is restored with updated sync timestamp.

[ ] STAGE 5: END-TO-END DISPENSING ACCURACY
    [ ] Dispense test: 100g target requested via app.
    [ ] Dispenser cuts off when load cell hits 100g.
    [ ] Physical scale verifies actual dispensed grains are within 98.5g - 101.5g (+/- 1.5g).
    [ ] App logs record contains targetGrams, actualGrams, durationSeconds, and PASS status.
    [ ] Export CSV function downloads valid feeding logs with all columns intact.

[ ] STAGE 6: FIELD READINESS SIGN-OFF
    [ ] Battery interlock blocks feeding below 11.2V.
    [ ] Low feed ultrasonic warning triggers banner when hopper drops below 20%.
    [ ] Complete system operates continuously for 24 hours without crash or memory leak.
```
