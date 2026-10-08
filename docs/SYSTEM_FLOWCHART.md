# Smart Poultry Feeder — App & Cloud Database System Flowchart
*Focusing on Mobile Application UX/UI, Cloud Synchronization, and Hardware Input/Output Interfaces*

---

## 1. App & Cloud Database Operational Flowchart

```mermaid
flowchart TD
  %% ==========================================
  %% SUBGRAPH 1: HARDWARE FINAL OUTPUTS & ACTUATION
  %% ==========================================
  subgraph HW ["1. Hardware Interface (Final Physical Outputs)"]
    HW_OUT["Hardware Sensor Final Outputs<br>- Hopper Feed Level (% and remaining kg)<br>- 12V Battery Pack (% and Volts)<br>- Live Digital Scale Reading (grams)<br>- Online Heartbeat & Operational Status"]
    HW_ACT["Physical Dispenser Actuation<br>- Receives Dispense Command with Target Grams<br>- Executes closed-loop dispensing via scale<br>- Halts on target reached or Emergency Stop"]
  end

  %% ==========================================
  %% SUBGRAPH 2: CLOUD DATABASE LAYER (Firebase RTDB)
  %% ==========================================
  subgraph DB ["2. Cloud Database (Firebase Realtime Database)"]
    DB_TEL[("Node: /telemetry<br>- feedLevelPercent: 78.0<br>- batteryVolts: 12.6<br>- batteryPercent: 92<br>- currentWeightGrams: 0.0<br>- status: 'idle' | 'dispensing'<br>- lastHeartbeat: timestamp")]
    
    DB_SCH[("Node: /schedules<br>- id: 'sch_1'<br>- label: 'Morning Routine'<br>- hour: 6, minute: 30<br>- targetGrams: 180.0<br>- isEnabled: true")]
    
    DB_CMD[("Node: /commands<br>- triggerManual: boolean<br>- targetGrams: 150.0<br>- emergencyStop: boolean<br>- timestamp: epoch")]
    
    DB_HIS[("Node: /history<br>- logId: 'log_101'<br>- timestamp: ISO date<br>- targetGrams vs actualGrams<br>- accuracyPercent & isSuccess<br>- batteryVolts & feedLevelPercent")]
  end

  %% ==========================================
  %% SUBGRAPH 3: APP STATE & DATA MANAGEMENT LAYER
  %% ==========================================
  subgraph SVC ["3. App State & Logic Layer (FeederService)"]
    SYNC["Real-Time Synchronization Engine<br>- Live stream listeners on /telemetry and /history<br>- Pull-to-refresh on-demand telemetry sync<br>- Optimistic local state updates"]
    
    RULES["Usability & Validation Logic (Nielsen Heuristics)<br>- Computes countdown to next feeding (e.g. in 2h 15m)<br>- Computes hopper days of supply left<br>- Aggregates total daily flock ration<br>- Validates schedule time duplicates and 20g-500g limits<br>- Manages 4-second Undo deletion stack"]
  end

  %% ==========================================
  %% SUBGRAPH 4: FLUTTER MOBILE APP SCREENS
  %% ==========================================
  subgraph APP ["4. Flutter Mobile Application"]
    SHELL["Adaptive Responsive Shell<br>- Mobile: Material 3 Bottom NavigationBar<br>- Tablet/Desktop: Side NavigationRail"]

    subgraph DASH ["Dashboard Screen (Visibility, Control & Error Prevention)"]
      D_STAT["Live Connection Status Badge & Sync Timestamp"]
      D_GAUGE["Hopper Capacity Gauge (Level %, kg, & Days Left)"]
      D_PWR["Solar System & 12V Battery Indicators"]
      D_NEXT["Next Automated Feeding Card with Live Countdown"]
      D_CHIP["Portion Presets (50g, 100g, 150g, 200g) + Fine Slider"]
      D_BTN["Dispense Button (Guarded: Disabled if Hopper < 5%)"]
      D_PROG["Active Dispensing Banner with Real-Time Scale Grams"]
      D_STOP["Immediate Emergency Stop / Abort Button"]
      D_INFO["System & Hardware Documentation Modal"]
    end

    subgraph SCHED ["Schedules Screen (User Freedom & Error Prevention)"]
      S_SUMM["Daily Flock Intake Summary (Active count & Total grams)"]
      S_LIST["Interactive Schedule Cards (Time, Label, Grams, Toggle)"]
      S_FORM["Add / Edit Modal Dialog with Time Picker & Presets"]
      S_VAL["Input Validation (Duplicate Time & Gram Limit Guard)"]
      S_UNDO["Delete Routine -> SnackBar with 4-Second UNDO Action"]
    end

    subgraph HIST ["History & Analytics Screen (Flexibility & Research Evaluation)"]
      H_METRIC["Chapter IV Performance Summary (Total Feeds, Avg %, Total kg)"]
      H_FILTER["Interactive Filter Chips (All, Scheduled Only, Manual Only)"]
      H_CARDS["Chronological Log Cards with Friendly Relative Times"]
      H_DEV["Accuracy Variance Badge (+/- grams and %)"]
      H_CSV["One-Tap CSV Export for Excel, SPSS, or Google Sheets"]
    end
  end

  %% ==========================================
  %% INTERACTION & DATA FLOW PIPELINES
  %% ==========================================
  
  %% Hardware <-> Cloud
  HW_OUT -->|Pushes telemetry packet every 10s| DB_TEL
  HW_ACT -->|Saves verified feeding log| DB_HIS
  DB_CMD -->|Hardware listens for dispense/stop| HW_ACT

  %% Cloud <-> Service Layer
  DB_TEL <==> SYNC
  DB_SCH <==> SYNC
  DB_CMD <== SYNC
  DB_HIS <==> SYNC
  
  SYNC <--> RULES
  RULES <--> SHELL

  %% Shell -> Screens
  SHELL --> DASH
  SHELL --> SCHED
  SHELL --> HIST

  %% User Actions -> Service/Database
  D_BTN -->|Confirm Dispense| DB_CMD
  D_STOP -->|Emergency Stop| DB_CMD
  S_VAL -->|Save Routine| DB_SCH
  S_UNDO -->|Delete / Restore| DB_SCH
  H_CSV -->|Export Dataset| CLIP["System Clipboard / CSV File"]

  %% STYLING
  classDef hwStyle fill:#FEF3C7,stroke:#D97706,stroke-width:1.5px,color:#92400E;
  classDef dbStyle fill:#F3E8FF,stroke:#A855F7,stroke-width:1.5px,color:#6B21A8;
  classDef svcStyle fill:#EFF6FF,stroke:#3B82F6,stroke-width:1.5px,color:#1E40AF;
  classDef appStyle fill:#CCFBF1,stroke:#0F766E,stroke-width:1.5px,color:#115E59;
  
  class HW_OUT,HW_ACT hwStyle;
  class DB_TEL,DB_SCH,DB_CMD,DB_HIS dbStyle;
  class SYNC,RULES svcStyle;
  class SHELL,D_STAT,D_GAUGE,D_PWR,D_NEXT,D_CHIP,D_BTN,D_PROG,D_STOP,D_INFO,S_SUMM,S_LIST,S_FORM,S_VAL,S_UNDO,H_METRIC,H_FILTER,H_CARDS,H_DEV,H_CSV appStyle;
```

---

## 2. Core Functional Workflows

### A. Real-Time Telemetry & Health Monitoring
1. **Hardware Output**: The physical hardware controller computes its final metrics:
   - Feed remaining ($0\% - 100\%$, $\sim 0.0 - 5.0\text{ kg}$).
   - 12V battery level ($0\% - 100\%$, $\text{Volts}$).
   - Current scale weight ($0.0\text{g}$).
   - Current operating state (`idle`, `dispensing`, `lowFeed`, `offline`).
2. **Cloud Bridge**: Pushes these metrics to Firebase RTDB node `/telemetry`.
3. **App Display**:
   - Updates the **Dashboard Gauge** and days-of-supply countdown.
   - Shows live connection status dot (green for online, amber for dispensing, red for offline).
   - Low-battery or low-hopper warning banners appear automatically if levels drop below $20\%$.

### B. Manual Dispensing & Emergency Stop Workflow
1. **User Action**: The farmer selects a portion (e.g. $150\text{g}$) and taps **DISPENSE NOW**.
2. **Error Prevention Check**:
   - The app verifies that the feeder is online and the hopper is not empty ($< 5\%$).
   - A confirmation dialog appears explaining the operation.
3. **Command Write**: The app writes `{ triggerManual: true, targetGrams: 150.0, emergencyStop: false }` to `/commands`.
4. **Active Dispensing Feedback**:
   - The dashboard dynamically displays a **live progress bar** showing weight accumulation from the scale ($0\text{g} \to 150\text{g}$).
   - An **Emergency Stop** button appears immediately.
5. **Abort Option**: Tapping **Emergency Stop** immediately writes `{ emergencyStop: true }` to `/commands`, causing the physical machine to snap the gate shut within milliseconds.
6. **Log Creation**: Once finished, a record is added to `/history` with target grams, actual dispensed grams, accuracy $\%$, and battery/hopper snapshot.

### C. Schedule Management Workflow
1. **View & Summary**: The farmer sees active routines and the total daily flock consumption (e.g. `3 Active Routines • 530g total`).
2. **Add / Edit Routine**:
   - Farmer taps a routine or the **+ Add Schedule** button.
   - Sets time via native time picker, enters label, and picks portion.
   - **Validation**: Rejects invalid portions ($< 20\text{g}$ or $> 500\text{g}$) and prevents duplicate times at the exact same hour and minute.
3. **Cloud Update**: Writes updated routine to `/schedules`.
4. **User Freedom (Undo)**: If a routine is deleted, the app displays a 4-second SnackBar with an **UNDO** action that restores the schedule at its exact index.

### D. Chapter IV Research Analytics & CSV Export
1. **Automatic Aggregation**: Computes overall performance metrics:
   - Total feedings conducted.
   - Average dispensing accuracy percentage.
   - Total feed distributed in kilograms.
2. **Filtering**: Interactive filter chips (`All`, `Scheduled Only`, `Manual Only`) allow the researcher to isolate specific feeding subsets.
3. **CSV Export**: The user taps the download icon to preview and copy the entire research dataset into clipboard, ready to paste directly into **Excel, SPSS, or Google Sheets** for statistical analysis.
