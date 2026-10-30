# AutomaticDispensing — Smart Solar-Powered Chicken Feeding System Agent Guidelines & Rules

## Repository & Version Control Rules
- **Automatic Push**: Commit and push every approved change and task completion to the remote repository (`origin/main`) so the user's GitHub repository is always up-to-date with all project modifications.
- **Security & Secret Hygiene**: Never commit sensitive information, secrets, API keys, passwords, or `.env` files. Ensure `.gitignore` continues to exclude `.env`, `.env.local`, `.env.development`, `.env.production`, `.env.test`, `.env.*`, `node_modules/`, `venv/`, `backend/.venv`, `.env.example`, `.env.example.local`, `.env.example.development`, `.env.example.production`, `.env.example.test`, `.env.example.*` files, virtual environments, build artifacts, and local configurations (including `firmware/include/secrets.h` and `app/lib/firebase_options.dart`).

## Git Commit Rules

When committing changes, **create separate commits per file**. Do NOT bundle multiple file changes into a single commit. Each file gets its own commit with a descriptive message specific to that file's changes.

For example, if `README.md`, `best-practice/claude-subagents.md`, and a skill file all changed:
- Commit 1: `git add README.md` → commit with README-specific message
- Commit 2: `git add best-practice/claude-subagents.md` → commit with subagents-doc-specific message
- Commit 3: `git add .claude/skills/weather-fetcher/SKILL.md` → commit with skill-specific message

This makes the git history cleaner and easier to review, revert, or cherry-pick individual changes.

---

## Project Stack & Key Paths
- **Mobile Client (`app/`):** Flutter 3.x (Dart), Liquid Glass iOS 26 Dark Forest UI, `ChangeNotifier` (`FeederService`), `HardwareAdapter` strategy (`FirebaseHardwareAdapter`, `DirectWifiHardwareAdapter` @ `http://192.168.4.1`, `MockHardwareAdapter`).
- **Embedded Firmware (`firmware/`):** ESP32-WROOM-32 (`espressif32`, Arduino/PlatformIO), HX711 (`GPIO 16/17`), MG996R Servo (`GPIO 13`), HC-SR04 (`GPIO 5/18`), DS3231 RTC (`GPIO 21/22`), 12V Battery ADC (`GPIO 34`).
- **Cloud Backend (`database.rules.json`, `data.json`):** Firebase Auth (Email/Password + Anonymous device fallback) + Firebase Realtime Database (`asia-southeast1`).
- **Second Brain Note:** `c:\Users\Jeho\Documents\Jeho's Second Brain\03 - Projects\Automatic Dispensing System\Automatic Dispensing System.md` (linked from `00 - Dashboard\Home.md`).

## Build & Verification Commands
- **Flutter Static Analysis:** `cd app; dart analyze lib/ test/`
- **Flutter Automated Tests (24 tests):** `cd app; flutter test --no-pub --timeout 30s`
- **Build Android APK:** `cd app; flutter build apk --debug`
- **ESP32 Firmware Compile:** `cd firmware; pio run`
- **ESP32 Flash & Monitor:** `cd firmware; pio run -t upload; pio device monitor -b 115200`

## Lean MVP & Hardware Safety Guardrails
- **Keep Scope Lean & Defense-Focused (`docs/MVP_PLAN.md`):** Prioritize reliable closed-loop/timed dispensing, accurate sensor telemetry, offline DS3231 schedule persistence, Dual-Mode Cloud/SoftAP fallback, and `.xlsx` thesis export. Do not introduce Cloud Functions, multi-tenant SaaS, BLE, or camera features before defense.
- **Physical Safety Interlocks:** Never remove the `11.2V` battery cutoff, `6s` stall/jam cutoff, `30s` dispense timeout, pre-actuation `/commands/dispense` deletion, or `0°` boot gate closure in `firmware/src/main.cpp`.
- **Evidence First:** Never mark physical hardware checks as verified without bench telemetry or trial logs; always run `dart analyze`, `flutter test --no-pub`, and `pio run` after code edits.
