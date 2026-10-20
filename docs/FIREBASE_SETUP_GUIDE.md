# Smart Chicken Feeder — Firebase Realtime Database Setup & Security Guide
*Step-by-Step Cloud Configuration, Security Rules, Seed Data, and ESP32 Integration*

---

## 1. Cloud Architecture Overview

The system uses **Google Firebase Realtime Database (RTDB)** as the low-latency, real-time message bus and data synchronization layer connecting the **Flutter Mobile App** and the **ESP32 Microcontroller**.

```
+-----------------------------------------------------------------------------------------+
|                               Firebase Realtime Database                                |
|                   https://<project-id>-default-rtdb.<region>.firebasedatabase.app       |
+-----------------------------------------------------------------------------------------+
       ^                                                                   ^
       | Firebase SDK Streams (.onValue, .onChildAdded)                     | HTTPS REST / Streaming
       v                                                                   v
+-------------------------------+                               +-------------------------+
|      Flutter Mobile App       |                               |     ESP32 Firmware      |
|  - Real-Time Sensor Gauges    |                               |  - HX711 Load Cell      |
|  - Manual Dispense Trigger    |                               |  - HC-SR04 Ultrasonic   |
|  - Schedule Synchronizer      |                               |  - MG996R Servo Gate    |
|  - CSV/Excel Export Tool      |                               |  - 12V Solar / Battery  |
+-------------------------------+                               +-------------------------+
```

### Why Firebase Realtime Database?
- **Sub-Second Latency**: Pushes live scale weight and hopper depth to the farmer's smartphone instantly.
- **Offline Persistence**: The mobile app caches the latest readings when disconnected and seamlessly reconnects.
- **REST Compatibility**: The ESP32 can send telemetry and receive commands using simple HTTPS `PUT`, `POST`, `GET`, and `DELETE` requests without running heavy client daemons.

---

## 2. Step-by-Step Firebase Project Setup

### Step 2.1: Create a Firebase Project
1. Open the [Firebase Console](https://console.firebase.google.com/) and sign in with your Google account.
2. Click **Add project** (or **Create a project**).
3. Project Name: Enter **`smart-chicken-feeder`** (or your preferred name).
4. Google Analytics: Optional for development (can be left disabled or enabled).
5. Click **Create Project** and wait for provisioning to finish.

### Step 2.2: Create the Realtime Database
1. In the left-hand navigation menu of the Firebase Console, navigate to **Build** → **Realtime Database**.
2. Click **Create Database**.
3. **Location Selection**:
   - Choose **Singapore (`asia-southeast1`)** if you are deploying in the Philippines or Southeast Asia for the lowest round-trip latency (<60ms).
   - Alternatively, choose `us-central1` or `europe-west1` depending on your deployment geography.
4. **Security Rules Preset**: Select **Start in test mode** for initial bench assembly (we will lock this down with production rules in Section 3).
5. Click **Enable**.
6. **Copy Database URL**: At the top of the Data tab, locate and copy your database reference URL:
   ```
   https://<your-project-id>-default-rtdb.asia-southeast1.firebasedatabase.app/
   ```

### Step 2.3: Retrieve the Web API Key
1. Click the **Project Settings** (gear icon ⚙️) next to *Project Overview* in the left sidebar.
2. In the **General** tab, scroll down to the **Web API Key** field.
3. Copy this key; it will be used in `firmware/include/secrets.h` if authentication tokens are enabled.

---

## 3. Database Security Rules

In Firebase Console, click on the **Rules** tab under **Realtime Database**. Replace the default rules with the configuration below and click **Publish**.

### Recommended Production Rules
These rules ensure that:
1. Only valid feeder paths can be modified.
2. Telemetry and commands have appropriate data-type validation.
3. Indexing on `timestamp` and `triggerType` optimizes data queries for CSV/Excel export.

```json
{
  "rules": {
    ".read": true,
    ".write": true,
    "feeders": {
      "$feeder_id": {
        "telemetry": {
          ".read": true,
          ".write": true,
          ".validate": "newData.hasChildren(['feedLevelPercent', 'batteryVolts', 'status'])"
        },
        "commands": {
          ".read": true,
          ".write": true
        },
        "schedules": {
          ".read": true,
          ".write": true
        },
        "logs": {
          ".read": true,
          ".write": true,
          ".indexOn": ["timestamp", "triggerType", "isSuccess"]
        }
      }
    },
    "telemetry": {
      ".read": true,
      ".write": true
    },
    "commands": {
      ".read": true,
      ".write": true
    },
    "logs": {
      ".read": true,
      ".write": true,
      ".indexOn": ["timestamp", "triggerType", "isSuccess"]
    }
  }
}
```

> [!NOTE]
> The top-level `telemetry`, `commands`, and `logs` keys provide backward compatibility with single-feeder firmware REST calls, while the `/feeders/$feeder_id` tree supports multi-coop farm deployments.

---

## 4. Initial Seed Data (JSON Schema)

To immediately populate the cloud database with realistic baseline data, you can import the JSON template below.

### How to Import Seed Data:
1. In the Firebase Console, go to **Realtime Database** → **Data** tab.
2. Click the three vertical dots (⋮) in the upper-right corner of the data pane.
3. Select **Import JSON**.
4. Upload a `.json` file containing the following structure (or paste it into your test script):

```json
{
  "telemetry": {
    "feedLevelPercent": 85.0,
    "batteryVolts": 12.65,
    "batteryPercent": 92,
    "currentWeightGrams": 0.0,
    "status": "idle",
    "lastHeartbeat": 1729440000000,
    "lastFedTimestamp": 1729425600000,
    "lastFedGrams": 180.5,
    "isSolarCharging": true
  },
  "commands": {
    "dispense": null
  },
  "schedules": [
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
  ],
  "logs": {
    "log_sample_01": {
      "timestamp": 1729425600000,
      "targetGrams": 180.0,
      "actualGrams": 181.2,
      "durationSeconds": 11,
      "triggerType": "Schedule",
      "isSuccess": true,
      "batteryVolts": 12.65,
      "feedLevelPercent": 85.0
    }
  }
}
```

---

## 5. Configuring ESP32 Firmware (`secrets.h`)

The ESP32 firmware includes a secure credentials structure to prevent accidental exposure of your private Wi-Fi passwords and Firebase API keys.

### Step 5.1: Create `secrets.h`
In the project directory, navigate to `firmware/include/`. Copy the template:
```bash
cp firmware/include/secrets.example.h firmware/include/secrets.h
```

### Step 5.2: Fill in Your Credentials
Open `firmware/include/secrets.h` in your editor and enter your local network and Firebase details:

```c
#pragma once
// Private credentials for physical ESP32 hardware
// This file is strictly excluded by .gitignore

// 1. Local Wi-Fi Network (Must be 2.4 GHz - ESP32 does NOT support 5 GHz)
#define WIFI_SSID          "Your-Farm-WiFi-SSID"
#define WIFI_PASSWORD      "Your-Farm-WiFi-Password"

// 2. Firebase Project Credentials (from Section 2.2 and 2.3)
#define FIREBASE_API_KEY   "AIzaSyYourGeneratedWebApiKeyHere"
#define FIREBASE_DB_URL    "https://smart-chicken-feeder-default-rtdb.asia-southeast1.firebasedatabase.app"

// 3. Optional Device Authentication
#define FIREBASE_USER_EMAIL    "device@smartfeeder.local"
#define FIREBASE_USER_PASSWORD "feeder-secure-pass-2026"
```

> [!CAUTION]
> - Never commit `secrets.h` to git.
> - Ensure your Wi-Fi router broadcasts a **2.4 GHz** frequency. Standard ESP32 DevKit V1 chips cannot detect 5 GHz networks.

### Step 5.3: Compile & Flash the Firmware
Build and flash the firmware onto your connected ESP32 via PlatformIO:
```bash
pio run -d firmware --target upload
```

---

## 6. Configuring the Flutter Mobile App

The Flutter mobile application contains a dedicated **`FirebaseHardwareAdapter`** located at [firebase_hardware_adapter.dart](file:///c:/Users/Jeho/Documents/AutomaticDispensing/app/lib/services/hardware/firebase_hardware_adapter.dart).

### To connect the mobile app to your Firebase project:
1. Download `google-services.json` from the Firebase Console (*Project Settings* → *Your Apps* → *Add Android App* with package name `com.example.smart_chicken_feeder`).
2. Place `google-services.json` inside:
   ```
   app/android/app/google-services.json
   ```
3. Rebuild the app:
   ```bash
   flutter build apk --debug
   ```

---

## 7. Cloud Verification & Testing Checklist

Once your Firebase project and ESP32 are configured, perform these verification checks:

| Test | Action | Expected Result |
|---|---|---|
| **1. Cloud Telemetry Stream** | Power on the ESP32 and open Firebase Console Data tab | `/telemetry` updates with live `batteryVolts`, `feedLevelPercent`, and `currentWeightGrams` every 10 seconds. |
| **2. App Real-Time Update** | Open the Flutter mobile app on your phone | Dashboard battery pod and hopper level reflect the Firebase values instantly. |
| **3. Remote Manual Feed** | In the mobile app, tap **Feed Now (5s)** | 1. App writes `{action: "DISPENSE", durationSeconds: 5}` to `/commands/dispense`.<br>2. ESP32 detects the command within 2s, opens servo gate.<br>3. ESP32 deletes `/commands/dispense` and posts new record to `/logs`. |
| **4. Cloud Tare Scale** | In Settings → Hardware Diagnostics, tap **Tare (0.0g)** | Scale on ESP32 zeros itself out, `/telemetry/currentWeightGrams` updates to `0.0`. |
| **5. Network Disconnect Test** | Turn off farm Wi-Fi | 1. ESP32 automatically activates `SmartFeeder-AP` local hotspot.<br>2. Mobile app shows warning banner *"Feeder connection lost. Showing last known data"*. |
