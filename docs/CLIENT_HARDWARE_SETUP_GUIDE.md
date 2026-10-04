# Smart Chicken Feeder — Hardware Bring-Up & Setup Guide
*A Step-by-Step Practical Guide for Fabricators & Assembly Teams*

---

## 1. Overview & System Diagram

This system consists of an **ESP32 microcontroller**, sensors for feed weight and hopper level, a servo-controlled dispensing gate, an accurate battery/solar monitor, and an offline Real-Time Clock (RTC).

```
[12V Solar Panel] ---> [Solar Charge Controller] ---> [12V Battery]
                                                            |
                                                   [Power Switch]
                                                            |
                                                   [LM2596 Buck (5V)]
                                                            |
      +-----------------------------------------------------+-----------------------+
      | (5V & GND)                                                                  |
      v                                                                             v
   [ESP32 DevKit] <--- I2C (21, 22) ---> [DS3231 RTC Module]                  [MG996R Servo Gate]
      |   ^                                                                     (GPIO 13)
      |   |--- DOUT (16), SCK (17) ----- [HX711 Amplifier] <--- [Load Cell Weighing Tray]
      |   |--- TRIG (5), ECHO (18) ----- [HC-SR04 Ultrasonic] (Inside Hopper Lid)
      |   |--- ADC (GPIO 34) <---------- [Battery Divider (40k/10k)] <--- 12V Battery
      v
 [2.4GHz Wi-Fi] ---> [Firebase Cloud Database] <---> [Mobile App]
```

---

## 2. Complete Wiring & Pinout Table

> ⚠️ **CRITICAL ELECTRICAL RULE #1 (Common Ground):**  
> All components (ESP32, Servo, HX711, Sensors, Buck Converter, Battery) **MUST share a common Ground (GND)**. If grounds are separated, the servo will jitter and sensor readings will be erratic.

> ⚠️ **CRITICAL ELECTRICAL RULE #2 (Check Voltage BEFORE Connecting ESP32):**  
> Before plugging the 5V Buck Converter into the ESP32 `VIN` pin, **use a digital multimeter** to measure the converter output. Ensure it reads **5.0V to 5.1V** (do NOT plug it in if it is 12V, or the ESP32 will burn).

### Pin Connections (ESP32 DevKit V1)

| Module | Component Pin | Connects to ESP32 Pin | Power Requirements | Notes |
|---|---|---|---|---|
| **Dispenser Gate** | Servo PWM (Orange/Yellow) | **GPIO 13** | 5V (from Buck Converter) & GND | Use high-torque metal gear servo (MG996R). Do *not* power from ESP32 3.3V pin. |
| **Load Cell (Weight)** | HX711 DOUT | **GPIO 16** | 5V & GND | Data output from scale amplifier |
| | HX711 SCK | **GPIO 17** | | Clock signal |
| **Hopper Level** | HC-SR04 TRIG | **GPIO 5** | 5V & GND | Trigger pulse |
| | HC-SR04 ECHO | **GPIO 18** | | ⚠️ Use voltage divider (1kΩ / 2kΩ) or 1kΩ resistor because Echo is 5V and ESP32 is 3.3V. |
| **Real-Time Clock** | DS3231 SDA | **GPIO 21** | 3.3V & GND | Default I2C Data (keeps time even during power loss) |
| | DS3231 SCL | **GPIO 22** | | Default I2C Clock |
| **Battery Monitor** | 12V Voltage Divider Out | **GPIO 34** | Analog Input Pin | Connect midpoint of 40kΩ and 10kΩ resistors across 12V battery. |

---

## 3. Step-by-Step Bring-Up Procedure (Test One by One)

Do **NOT** wire everything at once. Test in 4 isolated stages:

### Stage 1: Power Subsystem Check (5 Minutes)
1. Connect 12V solar panel to the Solar Charge Controller input.
2. Connect 12V Lead-Acid or LiFePO4 battery to the controller battery terminals. Verify the controller lights turn on.
3. Wire the 12V output through a mechanical power switch to the LM2596 DC-DC Buck converter.
4. Adjust the brass screw on the LM2596 buck converter until your multimeter measures **exactly 5.0V**.
5. Only then connect the 5V line to the ESP32 `VIN` pin and servo power rail.

### Stage 2: Gate & Servo Mechanical Test
1. Mount the dispenser gate / auger to the bottom of the hopper.
2. Ensure the gate moves freely by hand with no mechanical binding or friction.
3. Power the ESP32 via USB and open the Serial Monitor at **115200 baud**.
4. Type `f` in the Serial Monitor. The servo gate should open smoothly to $90^\circ$ and close back to $0^\circ$.
5. If the servo jitters or resets the ESP32: Add a $1000\mu\text{F}$ capacitor across the servo 5V and GND power rails.

### Stage 3: Scale Calibration (Crucial for Accurate Grams)
1. Mount the weighing tray onto the load cell bar. Make sure the tray does **not touch the sides** or frame of the coop.
2. Ensure the load cell arrow points downwards in the direction of weight force.
3. Place a known calibration weight on the tray (e.g., an unopened 500 mL water bottle = exactly $500\text{g}$, or a digital kitchen scale weight).
4. If the Serial Monitor reports a different weight, adjust `LOADCELL_CAL_FACTOR` in `config.h` until the readout matches the actual weight within $\pm 2\text{g}$.

### Stage 4: Ultrasonic Hopper Depth Calibration
1. Measure the physical depth of the hopper with a tape measure:
   - Distance from sensor face to hopper empty floor: update `HOPPER_EMPTY_CM` (default: 30 cm).
   - Distance from sensor face when hopper is full of chicken pellets: update `HOPPER_FULL_CM` (default: 5 cm).
2. Check Serial Monitor telemetry: when empty, it should report ~0%; when full, it should report ~100%.

---

## 4. How the Machine Connects to the Mobile App

1. The ESP32 connects to the local farm / coop Wi-Fi (2.4 GHz).
2. It pushes real-time telemetry (feed level %, battery voltage, scale grams, next schedule) to the Firebase Realtime Database.
3. When the user taps **"DISPENSE NOW"** on the mobile phone:
   - The app writes a command flag to Firebase.
   - The ESP32 detects the flag within 1 second.
   - The gate opens, dispenses feed until the load cell reaches the target grams, closes the gate, and logs the empirical results.
4. Even if Wi-Fi drops, the DS3231 RTC chip triggers scheduled automated feeds offline on time!

---

## 5. Remote Troubleshooting Checklist

| Symptom | Probable Cause | Action |
|---|---|---|
| **ESP32 resets whenever servo opens** | Voltage drop caused by servo surge current | Power servo directly from the 5V Buck converter, not the ESP32 3.3V pin. Add a $1000\mu\text{F}$ capacitor across 5V and GND. |
| **Load cell weight fluctuates randomly** | Loose wires or tray touching mechanical frame | Ensure load cell wires (Red, Black, White, Green) are soldered firmly to HX711. Ensure weighing platform has clear mechanical clearance. |
| **Ultrasonic sensor reads 0% or -1** | Echo pin wire loose or sensor blocked | Verify TRIG is on GPIO 5 and ECHO is on GPIO 18. Ensure sensor face is perpendicular to feed surface. |
| **RTC time is incorrect** | CR2032 backup coin cell is dead or unseated | Insert a fresh CR2032 3V coin cell battery into the DS3231 module. |
| **App shows "Offline"** | 2.4 GHz Wi-Fi credentials or weak signal at coop | Ensure coop router supports 2.4 GHz (ESP32 does not support 5 GHz Wi-Fi). Check `secrets.h` Wi-Fi credentials. |
