#!/usr/bin/env python3
"""
Smart Chicken Feeder — Cloud Hardware Simulator
Simulates physical ESP32 controller, HX711 load cell, HC-SR04 ultrasonic sensor,
solar charging, and MG996R servo dispenser against Firebase Realtime Database.

Aligned with hardened ESP32 firmware protocol:
- Purges pre-existing stale commands on boot without actuating the dispenser.
- Validates command freshness (<= 60s), `status == "pending"`, and deduplicates command IDs.
- Consumes `/commands/dispense` BEFORE opening the gate and writes `inProgress` / `completed` / `aborted`
  acknowledgements to `/commands/latest`.
- Polls `/commands/stop` during dispensing for sub-second emergency stop cutoff.
- Supports `SERVO_TEST` separately from `DISPENSE`.
- Supports optional `FIREBASE_AUTH_TOKEN` or `FIREBASE_API_KEY` + email/password authentication.
"""

import json
import os
import random
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

# Ensure UTF-8 output on Windows consoles
if sys.platform == "win32":
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass

DATABASE_URL = os.environ.get(
    "FIREBASE_DATABASE_URL",
    "https://smart-chicken-feeder-33bec-default-rtdb.asia-southeast1.firebasedatabase.app",
).rstrip("/")

COMMAND_MAX_AGE_MS = 60_000
MAX_DISPENSE_DURATION_SEC = 60
MAX_DISPENSE_GRAMS = 2000.0

# Simulated State
state = {
    "feedLevelPercent": 85.0,
    "batteryVolts": 12.65,
    "batteryPercent": 92,
    "currentWeightGrams": 0.0,
    "status": "idle",
    "isSolarCharging": True,
    "lastFedGrams": 180.0,
    "lastFedTimestamp": int(time.time() * 1000) - 7_200_000,
    "lastHeartbeat": int(time.time() * 1000),
}

running = True
stop_requested = threading.Event()
last_executed_cmd_id = ""
executed_schedule_slots = set()

_cached_token = os.environ.get("FIREBASE_AUTH_TOKEN", "").strip()
_token_expiry = float("inf") if _cached_token else 0.0
_token_lock = threading.Lock()


def resolve_auth_token(force_refresh=False):
    """Obtains an ID token from env or Firebase IdentityToolkit if FIREBASE_API_KEY is set."""
    global _cached_token, _token_expiry
    with _token_lock:
        if not force_refresh and _cached_token and time.time() < _token_expiry:
            return _cached_token

        api_key = os.environ.get("FIREBASE_API_KEY", "").strip()
        if not api_key:
            return _cached_token or None

        email = os.environ.get("FIREBASE_USER_EMAIL", "").strip()
        password = os.environ.get("FIREBASE_USER_PASSWORD", "").strip()
        if email and password:
            endpoint = f"https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key={api_key}"
            payload = {"email": email, "password": password, "returnSecureToken": True}
        else:
            endpoint = f"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key={api_key}"
            payload = {"returnSecureToken": True}

        try:
            req = urllib.request.Request(
                endpoint,
                data=json.dumps(payload).encode("utf-8"),
                method="POST",
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req, timeout=5) as resp:
                body = json.loads(resp.read().decode("utf-8"))
                token = body.get("idToken")
                expires_in = int(body.get("expiresIn", "3600"))
                if token:
                    _cached_token = token
                    _token_expiry = time.time() + max(60, expires_in - 300)
                    return _cached_token
        except Exception as exc:
            print(f"[Auth Warning] IdentityToolkit token request failed: {exc}")
        return None


def build_url(path):
    base = f"{DATABASE_URL}/{path}.json"
    token = resolve_auth_token(False)
    if token:
        return f"{base}?{urllib.parse.urlencode({'auth': token})}"
    return base


def http_get(path):
    req = urllib.request.Request(
        build_url(path),
        headers={"User-Agent": "ESP32-Hardware-Simulator/2.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            data = resp.read().decode("utf-8")
            return json.loads(data) if data and data != "null" else None
    except urllib.error.HTTPError as err:
        if err.code in (401, 403):
            print(f"\n[Auth Error GET /{path}]: HTTP {err.code} permission denied")
        return None
    except Exception:
        return None


def http_put(path, payload):
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        build_url(path),
        data=data,
        method="PUT",
        headers={
            "Content-Type": "application/json",
            "User-Agent": "ESP32-Hardware-Simulator/2.0",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            return resp.getcode() == 200
    except urllib.error.HTTPError as err:
        print(f"\n[HTTP Error PUT /{path}]: HTTP {err.code}")
        return False
    except Exception as exc:
        print(f"\n[Error PUT /{path}]: {exc}")
        return False


def http_delete(path):
    req = urllib.request.Request(
        build_url(path),
        method="DELETE",
        headers={"User-Agent": "ESP32-Hardware-Simulator/2.0"},
    )
    try:
        with urllib.request.urlopen(req, timeout=4) as resp:
            return resp.getcode() == 200
    except Exception:
        return False


def update_command_ack(cmd_id, action, status, actual_grams=0.0, error_msg=None):
    payload = {
        "id": cmd_id or f"cmd_{int(time.time() * 1000)}",
        "action": action,
        "status": status,
        "actualGrams": round(float(actual_grams), 1),
        "timestamp": int(time.time() * 1000),
    }
    if error_msg:
        payload["errorMessage"] = error_msg
    http_put("commands/latest", payload)


def purge_stale_commands_on_boot():
    global last_executed_cmd_id
    stale = http_get("commands/dispense")
    if isinstance(stale, dict):
        stale_id = str(stale.get("id", ""))
        action = str(stale.get("action", "UNKNOWN"))
        print(f"  [Boot Safety] Purging pre-boot queued command '{stale_id}' ({action}) without motor actuation.")
        http_delete("commands/dispense")
        http_delete("commands/stop")
        if stale_id:
            last_executed_cmd_id = stale_id
            update_command_ack(
                stale_id,
                action,
                "timeout",
                0.0,
                "Cleared pre-boot stale command on simulator startup",
            )


def check_cloud_emergency_stop():
    stop_cmd = http_get("commands/stop")
    if isinstance(stop_cmd, dict):
        act = str(stop_cmd.get("action", "")).upper()
        if act in ("STOP", "EMERGENCY_STOP"):
            http_delete("commands/stop")
            http_delete("commands/dispense")
            return True
    disp_cmd = http_get("commands/dispense")
    if isinstance(disp_cmd, dict):
        act = str(disp_cmd.get("action", "")).upper()
        if act in ("STOP", "EMERGENCY_STOP"):
            http_delete("commands/dispense")
            http_delete("commands/stop")
            return True
    return False


def simulate_dispense(cmd_id, target_grams, duration_seconds=5, trigger_type="Manual"):
    global state
    duration_seconds = max(1, min(int(duration_seconds), MAX_DISPENSE_DURATION_SEC))
    target_grams = max(1.0, min(float(target_grams if target_grams > 0 else duration_seconds * 20.0), MAX_DISPENSE_GRAMS))

    print(
        f"\n>> [SERVO ACTUATION] Opening Dispenser Gate! Target: {target_grams}g over {duration_seconds}s (Trigger: {trigger_type})"
    )
    stop_requested.clear()
    state["status"] = "dispensing"
    update_command_ack(cmd_id, "DISPENSE", "inProgress", 0.0)

    steps = max(2, min(20, duration_seconds * 2))
    sleep_interval = max(0.25, duration_seconds / steps)

    current_g = 0.0
    aborted = False
    for _ in range(1, steps + 1):
        if not running or stop_requested.is_set() or state["status"] != "dispensing" or check_cloud_emergency_stop():
            print(">> [EMERGENCY STOP] Dispense aborted mid-cycle! Closing servo gate immediately.")
            aborted = True
            break

        increment = (target_grams / steps) * random.uniform(0.94, 1.06)
        current_g += increment
        state["currentWeightGrams"] = round(current_g, 1)
        state["lastHeartbeat"] = int(time.time() * 1000)
        http_put("telemetry", state)
        print(f"   [Scale Weight]: {state['currentWeightGrams']}g / {target_grams}g...")
        time.sleep(sleep_interval)

    now_ms = int(time.time() * 1000)
    if aborted:
        final_actual = round(current_g, 1)
        state["currentWeightGrams"] = 0.0
        state["status"] = "idle"
        state["lastHeartbeat"] = now_ms
        http_put("telemetry", state)
        update_command_ack(cmd_id, "DISPENSE", "aborted", final_actual, "Aborted by emergency stop")
        log_id = f"log_{now_ms}"
        http_put(
            f"logs/{log_id}",
            {
                "id": log_id,
                "timestamp": now_ms,
                "targetGrams": float(target_grams),
                "actualGrams": float(final_actual),
                "durationSeconds": max(1, int(duration_seconds / 2)),
                "triggerType": f"{trigger_type} (Aborted)",
                "isSuccess": False,
                "batteryVolts": state["batteryVolts"],
                "feedLevelPercent": state["feedLevelPercent"],
            },
        )
        return

    final_actual = round(target_grams + random.uniform(-1.5, 1.5), 1)
    state["currentWeightGrams"] = final_actual
    state["lastFedGrams"] = final_actual
    state["lastFedTimestamp"] = now_ms
    state["feedLevelPercent"] = max(5.0, round(state["feedLevelPercent"] - (final_actual / 50.0), 1))
    state["status"] = "lowFeed" if state["feedLevelPercent"] < 20.0 else "idle"
    state["lastHeartbeat"] = now_ms
    http_put("telemetry", state)
    update_command_ack(cmd_id, "DISPENSE", "completed", final_actual)

    print(f">> [DISPENSE COMPLETE] Gate closed at {final_actual}g! Writing feeding log to Firebase...")

    log_id = f"log_{now_ms}"
    log_entry = {
        "id": log_id,
        "timestamp": now_ms,
        "targetGrams": float(target_grams),
        "actualGrams": float(final_actual),
        "durationSeconds": int(duration_seconds),
        "triggerType": trigger_type,
        "isSuccess": True,
        "batteryVolts": state["batteryVolts"],
        "feedLevelPercent": state["feedLevelPercent"],
    }
    http_put(f"logs/{log_id}", log_entry)
    print(f">> [LOG SAVED] Log ID: {log_id} recorded in Firebase (Type: {trigger_type}).\n")


def command_listener_loop():
    global state, running, last_executed_cmd_id
    while running:
        try:
            cmd = http_get("commands/dispense")
            if cmd and isinstance(cmd, dict):
                cmd_id = str(cmd.get("id", ""))
                action = str(cmd.get("action", "")).upper()
                status = str(cmd.get("status", "pending")).lower()
                cmd_ts = int(cmd.get("timestamp", 0) or 0)
                now_ms = int(time.time() * 1000)

                if status != "pending":
                    http_delete("commands/dispense")
                    continue

                if cmd_id and cmd_id == last_executed_cmd_id:
                    http_delete("commands/dispense")
                    continue

                if action not in ("STOP", "EMERGENCY_STOP") and cmd_ts > 946_684_800_000:
                    if now_ms > cmd_ts and (now_ms - cmd_ts) > COMMAND_MAX_AGE_MS:
                        print(f"\n>> [STALE COMMAND REJECTED] ID={cmd_id} age={(now_ms - cmd_ts) // 1000}s > 60s")
                        http_delete("commands/dispense")
                        last_executed_cmd_id = cmd_id
                        update_command_ack(cmd_id, action, "timeout", 0.0, "Stale command expired (>60s)")
                        continue

                # Consume command before execution so reconnects never replay it
                http_delete("commands/dispense")
                if cmd_id:
                    last_executed_cmd_id = cmd_id

                print(f"\n>> [COMMAND DETECTED FROM APP] ID: {cmd_id} | Action: {action}")

                if action in ("DISPENSE", "TRIGGER_MANUAL"):
                    slot_key = str(cmd.get("scheduleSlotKey", ""))
                    if slot_key and slot_key in executed_schedule_slots:
                        print(f">> [DEDUP] Schedule slot {slot_key} already executed; skipping.")
                        continue
                    if slot_key:
                        executed_schedule_slots.add(slot_key)

                    duration = int(cmd.get("durationSeconds", 5))
                    target = float(cmd.get("targetGrams", 0.0) or (duration * 20.0))
                    trigger = str(cmd.get("triggerType", "Manual"))
                    simulate_dispense(cmd_id, target, duration, trigger_type=trigger)

                elif action in ("STOP", "EMERGENCY_STOP"):
                    print(">> [STOP COMMAND] Immediate servo gate closure!")
                    stop_requested.set()
                    state["status"] = "idle"
                    http_delete("commands/stop")
                    http_put("telemetry", state)
                    update_command_ack(cmd_id, "STOP", "completed", 0.0)

                elif action in ("TARE", "TARE_SCALE"):
                    print(">> [TARE COMMAND] Scale zeroed to 0.0g!")
                    state["currentWeightGrams"] = 0.0
                    state["lastHeartbeat"] = now_ms
                    http_put("telemetry", state)
                    update_command_ack(cmd_id, "TARE_SCALE", "completed", 0.0)

                elif action in ("CALIBRATE", "CALIBRATE_SCALE"):
                    target = float(cmd.get("targetGrams", 500.0))
                    print(f">> [CALIBRATION COMMAND] Scale calibrated to {target}g reference weight!")
                    state["lastHeartbeat"] = now_ms
                    http_put("telemetry", state)
                    update_command_ack(cmd_id, "CALIBRATE_SCALE", "completed", target)

                elif action in ("SERVO_TEST", "SET_SERVO_ANGLE"):
                    angle = max(0, min(90, int(cmd.get("servoAngle", cmd.get("targetGrams", 0)))))
                    print(f">> [SERVO TEST] Positioning MG996R gate to {angle}° (auto-closes in 10s if open)")
                    state["lastHeartbeat"] = now_ms
                    http_put("telemetry", state)
                    update_command_ack(cmd_id, "SERVO_TEST", "completed", float(angle))

                else:
                    update_command_ack(cmd_id, action, "failed", 0.0, f"Unsupported action: {action}")

        except Exception:
            pass

        time.sleep(0.8)


def schedule_watcher_loop():
    global state, running
    print("  Scheduler: Active - Monitoring Firebase /schedules.json for autonomous execution")

    while running:
        try:
            now = time.localtime()
            weekday_1_based = now.tm_wday + 1  # 1 = Mon ... 7 = Sun

            schedules_data = http_get("schedules")
            if schedules_data:
                items = []
                if isinstance(schedules_data, dict):
                    for k, v in schedules_data.items():
                        if isinstance(v, dict):
                            item = dict(v)
                            item["id"] = k
                            items.append(item)
                elif isinstance(schedules_data, list):
                    for i, v in enumerate(schedules_data):
                        if isinstance(v, dict):
                            item = dict(v)
                            item["id"] = item.get("id", f"sch_{i}")
                            items.append(item)

                for s in items:
                    if not s.get("isEnabled", False):
                        continue

                    s_hour = int(s.get("hour", -1))
                    s_minute = int(s.get("minute", -1))
                    s_id = str(s.get("id", ""))
                    s_label = str(s.get("label", "Routine Feeding"))
                    s_duration = int(s.get("durationSeconds", 5))
                    s_target = float(s.get("targetGrams", s_duration * 20.0))
                    days_of_week = s.get("daysOfWeek", [1, 2, 3, 4, 5, 6, 7])

                    if isinstance(days_of_week, list) and len(days_of_week) > 0:
                        if weekday_1_based not in days_of_week:
                            continue

                    if s_hour == now.tm_hour and s_minute == now.tm_min:
                        slot_key = f"{now.tm_year}-{now.tm_mon}-{now.tm_mday}_{s_hour}:{s_minute}_{s_id}"
                        if slot_key not in executed_schedule_slots and state["status"] != "dispensing":
                            executed_schedule_slots.add(slot_key)
                            print("\n========================================================")
                            print(f">> [SCHEDULE TRIGGERED] Time: {now.tm_hour:02d}:{now.tm_min:02d}")
                            print(f"   Executing Routine: '{s_label}' (ID: {s_id})")
                            print(f"   Target: {s_target}g | Duration: {s_duration}s")
                            print("========================================================")
                            simulate_dispense(
                                f"sch_auto_{int(time.time() * 1000)}",
                                s_target,
                                s_duration,
                                trigger_type=f"Schedule ({s_label})",
                            )

        except Exception:
            pass

        time.sleep(3.0)


def telemetry_heartbeat_loop():
    global state, running
    while running:
        try:
            state["lastHeartbeat"] = int(time.time() * 1000)

            if state["isSolarCharging"]:
                state["batteryVolts"] = round(12.65 + random.uniform(-0.02, 0.04), 2)
                state["batteryPercent"] = min(100, int(92 + random.uniform(0, 2)))
            else:
                state["batteryVolts"] = round(12.35 + random.uniform(-0.02, 0.02), 2)
                state["batteryPercent"] = 85

            http_put("telemetry", state)
            sys.stdout.write(
                f"\r[HEARTBEAT] Time: {time.strftime('%H:%M:%S')} | Battery: {state['batteryVolts']}V "
                f"({state['batteryPercent']}%) | Hopper: {state['feedLevelPercent']}% | Status: {state['status'].upper()}   "
            )
            sys.stdout.flush()
        except Exception:
            pass

        time.sleep(2.5)


def main():
    global running
    print("=" * 72)
    print("  SMART CHICKEN FEEDER - CLOUD HARDWARE SIMULATOR (v2.0)")
    print(f"  Connected to: {DATABASE_URL}")
    print("=" * 72)

    purge_stale_commands_on_boot()

    print("  Status: Active - Sending live heartbeats and listening for commands")
    print("-" * 72)

    t_cmd = threading.Thread(target=command_listener_loop, daemon=True)
    t_tel = threading.Thread(target=telemetry_heartbeat_loop, daemon=True)
    t_sch = threading.Thread(target=schedule_watcher_loop, daemon=True)

    t_cmd.start()
    t_tel.start()
    t_sch.start()

    try:
        while running:
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\nStopping simulator...")
        running = False


if __name__ == "__main__":
    main()
