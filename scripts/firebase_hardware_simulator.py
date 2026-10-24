#!/usr/bin/env python3
"""
Smart Chicken Feeder — Cloud Hardware Simulator
Simulates physical ESP32 controller, HX711 load cell, HC-SR04 ultrasonic sensor,
solar charging, and MG996R servo dispenser against Firebase Realtime Database.

This allows full interactive testing of the Flutter mobile app without physical hardware!
"""

import urllib.request
import urllib.error
import json
import time
import sys
import threading
import random

# Ensure UTF-8 output on Windows consoles
if sys.platform == 'win32':
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass

DATABASE_URL = "https://smart-chicken-feeder-33bec-default-rtdb.asia-southeast1.firebasedatabase.app"

# Simulated State
state = {
    "feedLevelPercent": 85.0,
    "batteryVolts": 12.65,
    "batteryPercent": 92,
    "currentWeightGrams": 0.0,
    "status": "idle",
    "isSolarCharging": True,
    "lastFedGrams": 180.0,
    "lastFedTimestamp": int(time.time() * 1000) - 7200000,
    "lastHeartbeat": int(time.time() * 1000)
}

running = True

def http_get(path):
    url = f"{DATABASE_URL}/{path}.json"
    req = urllib.request.Request(url, headers={'User-Agent': 'ESP32-Hardware-Simulator/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = resp.read().decode('utf-8')
            return json.loads(data) if data and data != 'null' else None
    except Exception:
        return None

def http_put(path, payload):
    url = f"{DATABASE_URL}/{path}.json"
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(url, data=data, method='PUT', headers={'Content-Type': 'application/json', 'User-Agent': 'ESP32-Hardware-Simulator/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            return resp.getcode() == 200
    except Exception as e:
        print(f"[Error PUT /{path}]: {e}")
        return False

def http_delete(path):
    url = f"{DATABASE_URL}/{path}.json"
    req = urllib.request.Request(url, method='DELETE', headers={'User-Agent': 'ESP32-Hardware-Simulator/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            return resp.getcode() == 200
    except Exception:
        return False

def simulate_dispense(target_grams, duration_seconds=5):
    global state
    print(f"\n>> [SERVO ACTUATION] Opening Dispenser Gate! Target: {target_grams}g over {duration_seconds}s")
    state["status"] = "dispensing"
    steps = 10
    sleep_interval = max(0.2, duration_seconds / steps)
    
    current_g = 0.0
    for i in range(1, steps + 1):
        if not running or state["status"] != "dispensing":
            print(">> [EMERGENCY STOP] Dispense aborted mid-cycle!")
            break
        # Simulate realistic granular feed flow
        increment = (target_grams / steps) * random.uniform(0.92, 1.08)
        current_g += increment
        state["currentWeightGrams"] = round(current_g, 1)
        state["lastHeartbeat"] = int(time.time() * 1000)
        http_put("telemetry", state)
        print(f"   [Scale Weight]: {state['currentWeightGrams']}g / {target_grams}g...")
        time.sleep(sleep_interval)

    # Slight mechanical variance (+/- 1-2g)
    final_actual = round(target_grams + random.uniform(-1.5, 2.5), 1)
    state["currentWeightGrams"] = final_actual
    state["lastFedGrams"] = final_actual
    state["lastFedTimestamp"] = int(time.time() * 1000)
    state["status"] = "idle"
    # Deduct a small amount from hopper
    state["feedLevelPercent"] = max(5.0, round(state["feedLevelPercent"] - (final_actual / 50.0), 1))
    state["lastHeartbeat"] = int(time.time() * 1000)
    http_put("telemetry", state)

    print(f">> [DISPENSE COMPLETE] Gate closed at {final_actual}g! Writing research log to Firebase...")

    # Log to /logs
    log_id = f"log_{int(time.time())}"
    log_entry = {
        "timestamp": int(time.time() * 1000),
        "targetGrams": float(target_grams),
        "actualGrams": float(final_actual),
        "durationSeconds": int(duration_seconds),
        "triggerType": "Manual",
        "isSuccess": True,
        "batteryVolts": state["batteryVolts"],
        "feedLevelPercent": state["feedLevelPercent"]
    }
    http_put(f"logs/{log_id}", log_entry)
    print(f">> [LOG SAVED] Log ID: {log_id} recorded in Firebase.\n")

def command_listener_loop():
    global state, running
    while running:
        try:
            cmd = http_get("commands/dispense")
            if cmd and isinstance(cmd, dict):
                action = str(cmd.get("action", "")).upper()
                print(f"\n>> [COMMAND DETECTED FROM APP] Action: {action}")

                if action in ["DISPENSE", "TRIGGER_MANUAL"]:
                    target = float(cmd.get("targetGrams", 150.0))
                    duration = int(cmd.get("durationSeconds", 5))
                    # Clear command from queue
                    http_delete("commands/dispense")
                    simulate_dispense(target, duration)

                elif action in ["STOP", "EMERGENCY_STOP"]:
                    print(">> [STOP COMMAND] Immediate servo gate closure!")
                    state["status"] = "idle"
                    http_delete("commands/dispense")
                    http_put("telemetry", state)

                elif action in ["TARE", "TARE_SCALE"]:
                    print(">> [TARE COMMAND] Scale zeroed to 0.0g!")
                    state["currentWeightGrams"] = 0.0
                    http_delete("commands/dispense")
                    http_put("telemetry", state)

                elif action in ["CALIBRATE", "CALIBRATE_SCALE"]:
                    target = float(cmd.get("targetGrams", 500.0))
                    print(f">> [CALIBRATION COMMAND] Scale calibrated to {target}g reference weight!")
                    http_delete("commands/dispense")
                    http_put("telemetry", state)

                else:
                    http_delete("commands/dispense")

        except Exception as e:
            pass

        time.sleep(1.0)

def telemetry_heartbeat_loop():
    global state, running
    while running:
        try:
            # Update heartbeat timestamp to current time
            state["lastHeartbeat"] = int(time.time() * 1000)
            
            # Subtle realistic solar and battery micro-fluctuations
            if state["isSolarCharging"]:
                state["batteryVolts"] = round(12.65 + random.uniform(-0.02, 0.04), 2)
                state["batteryPercent"] = min(100, int(92 + random.uniform(0, 2)))
            else:
                state["batteryVolts"] = round(12.35 + random.uniform(-0.02, 0.02), 2)
                state["batteryPercent"] = 85

            http_put("telemetry", state)
            sys.stdout.write(f"\r[HEARTBEAT] Time: {time.strftime('%H:%M:%S')} | Battery: {state['batteryVolts']}V ({state['batteryPercent']}%) | Hopper: {state['feedLevelPercent']}% | Status: {state['status'].upper()}   ")
            sys.stdout.flush()
        except Exception as e:
            pass

        time.sleep(2.5)

def main():
    global running, state
    print("=" * 72)
    print("  SMART CHICKEN FEEDER - CLOUD HARDWARE SIMULATOR")
    print(f"  Connected to: {DATABASE_URL}")
    print("=" * 72)
    print("  Status: Active - Sending live heartbeats and listening for commands")
    print("-" * 72)

    t_cmd = threading.Thread(target=command_listener_loop, daemon=True)
    t_tel = threading.Thread(target=telemetry_heartbeat_loop, daemon=True)

    t_cmd.start()
    t_tel.start()

    try:
        while running:
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nStopping simulator...")
        running = False

if __name__ == "__main__":
    main()
