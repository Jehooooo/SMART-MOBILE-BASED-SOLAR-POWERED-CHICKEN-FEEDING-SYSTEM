# Smart Chicken Feeder — Hardware Bench-Testing & Assembly Wiring Checklist
*Practical Bring-Up, Calibration, and Pre-Commissioning Protocol for Engineering Teams*

---

## 1. Safety & Required Equipment

Before assembling the physical electronic enclosure or connecting power, prepare the following workbench tools:

### Required Tools & Equipment
- **Digital Multimeter (DMM)** with probe leads (essential for voltage adjustment).
- **Small Flathead Precision Screwdriver** (for adjusting the LM2596 buck converter trim potentiometer).
- **Soldering Iron & Heat Shrink** (or quality screw terminal blocks).
- **Standard Reference Weight**:
  - Precision calibration weights (100g, 200g, 500g, or 1000g), OR
  - An unopened standard **500 mL commercial bottled water** ($500.0\text{g} \pm 1\text{g}$ at room temperature).
- **Computer** with USB micro-B / Type-C cable for ESP32 serial monitoring and PlatformIO flashing.
- **Android Smartphone** with the installed `app-debug.apk`.

---

## 2. Critical Safety Rule: Voltage Regulation BEFORE Connecting ESP32

> [!CAUTION]
> ### NEVER connect the ESP32 or sensors to the LM2596 Buck Converter without verifying output voltage first!
> Factory LM2596 modules often arrive with their multi-turn potentiometer adjusted to output **12V or higher** (matching the input). Plugging this directly into the ESP32 `VIN` pin or the servo will immediately fry the microcontroller, sensors, and servo electronics.

### Voltage Tuning Procedure:
```
[12V Battery] ---> [LM2596 IN+ / IN-] ---> [Multimeter Probes on OUT+ / OUT-]
                                              Turn screw counter-clockwise until:
                                              Strictly 5.00V - 5.05V DC
```
1. Connect the 12V battery (or 12V bench power supply) to the **`IN+`** and **`IN-`** terminals of the LM2596.
2. Set your digital multimeter to **DC Voltage** ($20\text{V}$ range).
3. Place the red probe on **`OUT+`** and the black probe on **`OUT-`**.
4. Using the precision screwdriver, turn the brass screw on the blue potentiometer **counter-clockwise** (typically 10–15 full turns) until the voltage drops to **exactly 5.00V to 5.05V DC**.
5. Disconnect power. The 5V bus is now calibrated and safe for the ESP32 and servo motor.

---

## 3. Complete Pin-by-Pin Wiring Checklist

All connections are mapped to the **ESP32 DevKit V1 (30-pin / 38-pin)**:

```
                                  ESP32 DevKit V1
                             +-----------------------+
                             | [USB]                 |
                   5V (Buck) | VIN               GND | Common Ground
                             | 3V3              GPIO |
                             | GND              GPIO |
                             | GPIO             GPIO |
                             | GPIO             GPIO |
           HC-SR04 TRIG <--- | GPIO 5        GPIO 18 | <--- HC-SR04 ECHO (via divider)
                             | GPIO          GPIO 19 |
                             | GPIO          GPIO 21 | <---> DS3231 SDA (I2C)
                             | GPIO          GPIO 22 | <---> DS3231 SCL (I2C)
            MG996R PWM <--- | GPIO 13       GPIO 23 |
            HX711 DOUT <--- | GPIO 16               |
             HX711 SCK <--- | GPIO 17       GPIO 34 | <--- 12V Battery Divider (40k/10k)
                             +-----------------------+
```

### Wiring Matrix

| Subsystem | Component Pin | ESP32 Pin | Power Rail | Critical Wiring Notes | Checked (✓) |
|---|---|---|---|---|---|
| **Power Input** | LM2596 `OUT+` | **VIN** | 5.0V Regulated | Supplies ESP32 internal LDO regulator. | [ ] |
| | LM2596 `OUT-` | **GND** | Ground | Connect to **Common Ground** rail. | [ ] |
| **Dispenser Gate** | Servo PWM (Orange/Yellow) | **GPIO 13** | 3.3V Logic | Metal gear MG996R servo signal. | [ ] |
| | Servo VCC (Red) | **LM2596 OUT+** | **5.0V (Direct)** | ⚠️ **DO NOT power from ESP32 pins!** | [ ] |
| | Servo GND (Brown/Black)| **Common GND** | Ground | Must share ground with ESP32. | [ ] |
| **Load Cell (HX711)**| HX711 DOUT | **GPIO 16** | 3.3V Logic | Serial data out from scale ADC. | [ ] |
| | HX711 SCK | **GPIO 17** | 3.3V Logic | Clock pulse to scale ADC. | [ ] |
| | HX711 VCC | **5V or 3.3V** | 5V / 3.3V | 5V gives better signal-to-noise ratio. | [ ] |
| | HX711 GND | **Common GND** | Ground | Ground reference for amplifier. | [ ] |
| **Load Cell Wires** | Red Wire | **E+** (Excitation +) | HX711 Terminal | Strain gauge bridge excitation positive. | [ ] |
| | Black Wire | **E-** (Excitation -) | HX711 Terminal | Strain gauge bridge ground. | [ ] |
| | White Wire | **A-** (Signal -) | HX711 Terminal | Differential measurement input. | [ ] |
| | Green Wire | **A+** (Signal +) | HX711 Terminal | Differential measurement input. | [ ] |
| **Hopper Ultrasonic**| HC-SR04 VCC | **5V (Buck)** | 5.0V | Ultrasonic transducers require 5V. | [ ] |
| | HC-SR04 GND | **Common GND** | Ground | Return path. | [ ] |
| | HC-SR04 TRIG | **GPIO 5** | 3.3V Output | 10µs pulse to start sound wave. | [ ] |
| | HC-SR04 ECHO | **GPIO 18** | **3.3V Divided** | ⚠️ **Use 1kΩ/2kΩ divider!** (Echo is 5V). | [ ] |
| **Real-Time Clock** | DS3231 VCC | **3.3V (ESP32)** | 3.3V | Low power clock backup. | [ ] |
| | DS3231 GND | **Common GND** | Ground | Reference ground. | [ ] |
| | DS3231 SDA | **GPIO 21** | 3.3V I2C | Default ESP32 I2C Data. | [ ] |
| | DS3231 SCL | **GPIO 22** | 3.3V I2C | Default ESP32 I2C Clock. | [ ] |
| **Battery Voltage** | Voltage Divider Mid | **GPIO 34** | 0.0V–3.0V DC | Input-only analog pin (ADC1 CH6). | [ ] |

---

## 4. Critical Circuit Isolation Diagrams

### 4.1. Common Ground Rail (Crucial for Signal Stability)
Every subsystem must return to a single unified ground bus. Floating grounds will cause the MG996R servo to jerk erratically and produce random spikes on the HX711 scale:

```
[12V Battery Negative] 
         |
         +---> [LM2596 IN-]
         |
         +---> [LM2596 OUT-]
         |
         +---> [ESP32 GND Pins]
         |
         +---> [MG996R Servo GND (Brown)]
         |
         +---> [HX711 GND]
         |
         +---> [HC-SR04 GND]
         |
         +---> [DS3231 GND]
         |
         +---> [10kΩ Battery Divider Resistor]
```

---

### 4.2. HC-SR04 Echo Voltage Divider (Protecting ESP32 GPIO 18)
The HC-SR04 operates at 5V and outputs 5V logic pulses on its `ECHO` pin. Because ESP32 GPIO pins are rated for **3.3V maximum**, connect a two-resistor divider:

```
[HC-SR04 ECHO (5V)] 
         |
      [1kΩ Resistor]
         |
         +--------------------> [ESP32 GPIO 18] (~3.3V Safe Logic)
         |
      [2kΩ Resistor]
         |
    [Common GND]
```
$$\text{Output Voltage} = 5.0\text{V} \times \frac{2\text{k}\Omega}{1\text{k}\Omega + 2\text{k}\Omega} = 3.33\text{V DC}$$

---

### 4.3. 12V Battery Voltage Divider (Into GPIO 34)
The Lead-Acid / Solar battery fluctuates between $11.5\text{V}$ (discharged) and $14.4\text{V}$ (bulk charging). Stepping down by a factor of 5 gives a safe 0–3.0V analog voltage:

```
[12V Battery Positive] 
         |
     [40kΩ Resistor] (or two 20kΩ in series)
         |
         +--------------------> [ESP32 GPIO 34 (ADC)]
         |
     [10kΩ Resistor]
         |
    [Common GND]
```
$$\text{Divider Ratio} = \frac{40\text{k}\Omega + 10\text{k}\Omega}{10\text{k}\Omega} = 5.0$$
$$\text{Max ADC Voltage at } 14.5\text{V} = \frac{14.5\text{V}}{5} = 2.90\text{V} < 3.3\text{V}$$

---

## 5. Step-by-Step Bring-Up & Verification Protocol

Follow this structured protocol sequentially. Do **not** proceed to the next step until the current subsystem passes.

```
+-----------------------------------------------------------------------------------+
|  [Stage 1: Power]  ->  [Stage 2: Servo]  ->  [Stage 3: Depth]  ->  [Stage 4: Scale] |
|       5.0V DMM            Sweep 0-90°          Echo Divider         Tare & 500g   |
+-----------------------------------------------------------------------------------+
```

---

### Stage 1: Power & Voltage Rail Verification
1. Turn on the main 12V battery switch.
2. Measure voltage at the LM2596 `OUT+` and `OUT-`: **Must read $5.00\text{V} \pm 0.05\text{V}$**.
3. Plug in the ESP32. Verify the red power LED on the ESP32 lights up steady.
4. Measure between the ESP32 `3V3` pin and `GND`: **Must read $3.28\text{V} - 3.32\text{V}$**.

---

### Stage 2: Dispenser Gate (MG996R Servo) Actuator Test
1. Connect servo signal to **GPIO 13**, VCC to **5V Buck**, GND to **Common Ground**.
2. Open the mobile app → Navigate to **Settings** → **Hardware Diagnostics & Calibration** → **Dispenser Gate Servo**.
3. Tap **Close (0°)**:
   - Verify the servo horn rotates fully to the closed position.
   - Verify there is no buzzing or physical binding against the hopper funnel.
4. Tap **Full Open (90°)**:
   - Verify the gate opens 90 degrees smoothly.
5. Tap **Pulse Test (2s)**:
   - Gate should open to 90°, hold for 2 seconds, and smoothly return to 0°.

---

### Stage 3: Hopper Ultrasonic Depth (HC-SR04) Verification
1. Position the HC-SR04 sensor facing down inside the top hopper lid.
2. In the mobile app Diagnostics screen, observe the **Hopper Depth** card:
   - Point the lid at a flat tabletop 20 cm away: App should read approximately $20\text{cm}$.
   - Block the sensor with your hand at 5 cm: App should read $5\text{cm}$ and hopper gauge should show near 100% full.
3. If distance reads `-1` or erratic values: Check the 1kΩ/2kΩ voltage divider on Echo (GPIO 18).

---

### Stage 4: Load Cell & Weighing Tray (HX711) Calibration
This establishes the measurement accuracy required for research validation ($\pm 1.5\text{g}$ empirical threshold).

#### Calibration Procedure:
1. Ensure the weighing tray is installed on top of the load cell with no feed or objects touching it.
2. Open the mobile app Diagnostics screen → Scroll to **Load Cell & Scale (HX711)**.
3. **Step 1 (Tare)**: Tap **Tare (0.0g)**.
   - The ESP32 clears the tare offset.
   - The live readout should display **`0.0 g`**.
4. **Step 2 (Reference Weight Factor)**:
   - Place an unopened 500 mL water bottle (or 500g test weight) squarely in the center of the tray.
   - Select the **500g** chip in the app.
   - Tap **Save Factor**.
   - The ESP32 calculates `currentCalFactor = rawUnits / 500.0` and stores it into active memory.
5. **Verification**:
   - Remove the weight: Scale should return to **`0.0 g`** ($\pm 0.5\text{g}$).
   - Replace the 500g weight: Scale should read **`500.0 g`** ($\pm 1.5\text{g}$).
   - Test with known items (e.g. 100g, 200g) to confirm linearity.

---

### Stage 5: DS3231 Real-Time Clock Power-Loss Check
1. In the app Settings, verify the system time matches your phone clock.
2. Disconnect the main battery switch. Wait 60 seconds with power completely off.
3. Reconnect the battery switch.
4. Open the serial monitor or app: Verify the timestamp remains continuous without resetting to 1970 or 2000 (confirming the DS3231 CR2032 coin cell battery is functional).

---

### Stage 6: Direct Wi-Fi SoftAP Off-Grid Test
1. On your smartphone, open Wi-Fi settings.
2. Locate and connect to network **`SmartFeeder-AP`** (Password: **`chickens123`**).
3. Open Chrome or Safari on your phone and navigate to:
   ```
   http://192.168.4.1/
   ```
4. Verify the web dashboard loads with live battery voltage, hopper level, and weight.
5. Tap **Dispense Feed (5s)** directly in the browser: Verify the dispenser gate opens for 5 seconds and returns to closed.

---

## 6. Hardware Troubleshooting & Fault Matrix

| Symptom | Probable Root Cause | Recommended Corrective Action |
|---|---|---|
| **ESP32 reboots in a loop when servo turns** | Servo is drawing peak current (>1.5A) from ESP32 3.3V/5V pin causing voltage dip | Move servo red wire directly to the LM2596 5V output. Add a $470\mu\text{F}$ capacitor across servo 5V and GND. |
| **Load cell reads constant `0.0g` or `nan`** | Swapped DOUT / SCK pins or disconnected excitation | Verify DOUT is GPIO 16 and SCK is GPIO 17. Check with DMM that $E+$ and $E-$ have ~4.3V across them. |
| **Load cell values drift continuously** | Strain gauge mechanical binding or loose mounting bolts | Ensure load cell arrow points in direction of gravity and spacer washers prevent tray from rubbing against frame. |
| **Ultrasonic sensor reads `-1` or timeout** | Echo voltage divider resistor values incorrect or open circuit | Verify 1kΩ / 2kΩ divider. Ensure ECHO wire connects to GPIO 18 and TRIG to GPIO 5. |
| **Battery voltage reads `0.0V` or incorrect** | Wrong resistor values on voltage divider or loose ground | Measure voltage at GPIO 34 with DMM: It should be exactly $V_{BAT} / 5.0$. Verify 40kΩ and 10kΩ resistors. |
| **`SmartFeeder-AP` hotspot does not appear** | Wi-Fi mode not set to `WIFI_AP_STA` or antenna obstructed | Inspect serial output at 115200 baud for `[SOFTAP] Direct Wi-Fi Active`. Check ESP32 onboard PCB antenna. |
