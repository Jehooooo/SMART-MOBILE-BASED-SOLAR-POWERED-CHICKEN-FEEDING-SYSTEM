# Smart Poultry Feeder — Comprehensive System Flowchart
*Based on Chapter II Methodology and Current System Implementation*

---

## 1. System Architecture & Operation Flowchart

```mermaid
flowchart TD
  %% ==========================================
  %% SUBGRAPH 1: POWER & HARDWARE SUBSYSTEM
  %% ==========================================
  subgraph HW ["1. Power & Hardware Subsystem"]
    SP["12V Monocrystalline Solar Panel"] --> CC["Solar Charge Controller"]
    CC --> BAT["12V Storage Battery (7Ah SLA / Li-ion)"]
    BAT --> VDIV["Voltage Divider (40k/10k to GPIO 34)"]
    BAT --> PSW["Mechanical Power Switch"]
    PSW --> BUCK["LM2596 DC-DC Buck Converter (12V to 5V)"]
    BUCK --> ESP_PWR["5V Regulated Power Rail"]
    
    RTC_MOD["DS3231 RTC Module (CR2032 Battery Backup)"]
    US_MOD["HC-SR04 Ultrasonic Sensor (Hopper Lid)"]
    LC_MOD["Load Cell & HX711 Amplifier (Weighing Tray)"]
    SERVO_MOD["MG996R Metal-Gear Servo Dispenser Gate"]
  end

  %% ==========================================
  %% SUBGRAPH 2: ESP32 FIRMWARE CORE
  %% ==========================================
  subgraph FW ["2. ESP32 Firmware Execution Loop"]
    BOOT["ESP32 System Boot & Hardware Init"] --> INIT_CHK{"Sensors & RTC OK?"}
    INIT_CHK -- Yes --> SBY["Idle Monitoring Loop (Every 10s)"]
    INIT_CHK -- No --> ERR_LOG["Log Hardware Fault to Firebase"]
    
    SBY --> READ_TEL["Read HC-SR04 Feed Level & Battery ADC"]
    READ_TEL --> PUSH_TEL["Sync Telemetry to Cloud Database"]
    
    PUSH_TEL --> TRIG_DEC{"Dispensing Trigger Detected?"}
    
    TRIG_DEC -- "RTC Schedule Match" --> DISP_START["Initialize Dispense Routine"]
    TRIG_DEC -- "Manual App Command" --> DISP_START
    TRIG_DEC -- "None" --> SBY
    
    DISP_START --> HOPPER_SAFE{"Hopper Level >= 5%?"}
    HOPPER_SAFE -- No --> BLK_DISP["Abort Dispense & Send Low-Feed Alert"]
    HOPPER_SAFE -- Yes --> TARE["Step 1: Tare Load Cell (Zero Weight)"]
    
    TARE --> OPEN_GATE["Step 2: Rotate Servo to 90 deg (Open Gate)"]
    OPEN_GATE --> WT_LOOP["Step 3: Read Weight in Grams via HX711"]
    
    WT_LOOP --> COND_CHK{"Target Weight Reached?"}
    COND_CHK -- Yes --> CLOSE_GATE["Step 4: Rotate Servo to 0 deg (Close Gate)"]
    COND_CHK -- "No & Time < 30s" --> WT_LOOP
    COND_CHK -- "Timeout (30s) or Cancel" --> CLOSE_GATE
    
    CLOSE_GATE --> LOG_REC["Generate Feeding Log (Target vs Actual, Accuracy %, Volts)"]
    LOG_REC --> PUSH_LOG["Upload Log & Notify App"]
    PUSH_LOG --> SBY
  end

  %% ==========================================
  %% SUBGRAPH 3: CLOUD DATABASE LAYER
  %% ==========================================
  subgraph CLOUD ["3. Cloud & Data Layer (Firebase Realtime DB)"]
    RTDB_TEL[("Node: /telemetry<br>- Feed Level %<br>- Battery Volts & %<br>- Scale Weight<br>- Online Status")]
    RTDB_SCH[("Node: /schedules<br>- Hour & Minute<br>- Target Grams<br>- Enable Toggle")]
    RTDB_CMD[("Node: /commands<br>- Manual Trigger Flag<br>- Selected Grams<br>- Emergency Stop")]
    RTDB_HIS[("Node: /history<br>- Empirical Logs<br>- Accuracy %<br>- Chapter IV Data")]
  end

  %% ==========================================
  %% SUBGRAPH 4: FLUTTER MOBILE APP
  %% ==========================================
  subgraph APP ["4. Flutter Mobile App (Nielsen Usability Enhanced)"]
    NAV["Responsive Layout Shell<br>- Mobile: NavigationBar<br>- Tablet/Desktop: NavigationRail"]
    
    DASH["Dashboard Screen<br>- Real-time Hopper Gauge & Days Left<br>- Solar & Battery V Indicators<br>- Next Feed Countdown (e.g. in 2h 15m)<br>- Preset Chips (50g-200g) & Fine Slider<br>- Emergency Stop Button<br>- Hardware Info Guide Modal"]
    
    SCHED["Schedules Screen<br>- Daily Intake Summary (Active & Total g)<br>- Add & Tap-to-Edit Routine Dialog<br>- Duplicate Time & Gram Validation<br>- Delete with 4-second Undo SnackBar"]
    
    HIST["History & Analytics Screen<br>- Performance Metrics (Total, Avg %, Total kg)<br>- Filter Chips (All, Scheduled, Manual)<br>- Sensor Snapshot (V, % at feeding time)<br>- CSV Export for Excel/SPSS/Sheets"]
  end

  %% ==========================================
  %% INTER-SUBSYSTEM CONNECTIONS
  %% ==========================================
  ESP_PWR -.-> BOOT
  RTC_MOD -. "I2C (GPIO 21, 22)" .-> SBY
  US_MOD -. "Trig: 5, Echo: 18" .-> READ_TEL
  VDIV -. "ADC (GPIO 34)" .-> READ_TEL
  LC_MOD -. "DOUT: 16, SCK: 17" .-> WT_LOOP
  SERVO_MOD -. "PWM (GPIO 13)" .-> OPEN_GATE
  SERVO_MOD -. "PWM (GPIO 13)" .-> CLOSE_GATE
  
  PUSH_TEL --> RTDB_TEL
  PUSH_LOG --> RTDB_HIS
  RTDB_CMD --> TRIG_DEC
  RTDB_SCH --> SBY
  
  NAV --> DASH
  NAV --> SCHED
  NAV --> HIST
  
  RTDB_TEL <==> DASH
  RTDB_CMD <== DASH
  RTDB_SCH <==> SCHED
  RTDB_HIS <==> HIST

  %% STYLING
  classDef hwStyle fill:#FEF3C7,stroke:#D97706,stroke-width:1.5px,color:#92400E;
  classDef fwStyle fill:#EFF6FF,stroke:#3B82F6,stroke-width:1.5px,color:#1E40AF;
  classDef cloudStyle fill:#F3E8FF,stroke:#A855F7,stroke-width:1.5px,color:#6B21A8;
  classDef appStyle fill:#CCFBF1,stroke:#0F766E,stroke-width:1.5px,color:#115E59;
  
  class SP,CC,BAT,VDIV,PSW,BUCK,ESP_PWR,RTC_MOD,US_MOD,LC_MOD,SERVO_MOD hwStyle;
  class BOOT,INIT_CHK,SBY,READ_TEL,PUSH_TEL,TRIG_DEC,DISP_START,HOPPER_SAFE,BLK_DISP,TARE,OPEN_GATE,WT_LOOP,COND_CHK,CLOSE_GATE,LOG_REC,PUSH_LOG,ERR_LOG fwStyle;
  class RTDB_TEL,RTDB_SCH,RTDB_CMD,RTDB_HIS cloudStyle;
  class NAV,DASH,SCHED,HIST appStyle;
```

---

## 2. Methodology Execution Breakdown

### Phase A: Hardware Energy & Sensory Acquisition
1. **Solar Harvesting**: A 12V Monocrystalline panel delivers charging current to the 12V lead-acid/Li-ion battery via the charge controller.
2. **Voltage Regulation**: LM2596 buck converter steps 12V down to a stable 5.0V for the ESP32 and high-torque MG996R servo motor.
3. **Continuous Diagnostics**:
   - **Battery Monitoring**: Precision resistor divider (40kΩ / 10kΩ) steps down 12V to $\le 3.0\text{V}$ for the ESP32 ADC on GPIO 34.
   - **Hopper Level Sensing**: Ultrasonic HC-SR04 mounted inside the hopper lid computes distance to pellets and translates it to capacity percentage.

### Phase B: Closed-Loop Dispensing Operation
Unlike traditional open-loop timers that drop inconsistent feed quantities, this system implements **closed-loop feedback**:
1. **Tare Execution**: The load cell scale is calibrated and zeroed before the gate opens.
2. **Servo Activation**: The MG996R metal-gear servo rotates to $90^\circ$ to open the gravity-fed dispenser chute.
3. **Real-Time Weight Feedback**: The HX711 analog-to-digital converter streams weight readings in grams at 10Hz/80Hz.
4. **Cutoff Decision**: As soon as `currentWeight >= targetGrams`, the servo closes to $0^\circ$ in milliseconds, achieving target accuracy within $\pm 2\text{g}$.
5. **Safety Guardrails**: A 30-second timeout halts operation and logs a warning if feed is jammed or empty.

### Phase C: Dual-Path Triggering & Offline Autonomy
- **Online (Mobile Cloud Trigger)**: The user triggers feeds or configures routines anywhere in the world via Firebase Realtime Database.
- **Offline Autonomy**: If the 2.4 GHz Wi-Fi disconnects, the **DS3231 RTC module** maintains battery-backed time and triggers scheduled feedings independently without missing a ration.

### Phase D: Chapter IV Research Analytics
Every feeding session records empirical data directly accessible in the mobile app and exportable to CSV:
- **Accuracy Variance**: Target Weight vs. Actual Dispensed Weight ($\text{Error} = \text{Actual} - \text{Target}$).
- **Dispense Accuracy %**: $100\% - \left(\frac{|\text{Target} - \text{Actual}|}{\text{Target}} \times 100\right)$.
- **Response Latency**: Elapsed seconds from command trigger to completed dispensing.
- **Autonomy Metrics**: Battery voltage curve and hopper consumption per day.
