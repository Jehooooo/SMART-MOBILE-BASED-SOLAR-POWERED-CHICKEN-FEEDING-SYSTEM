# Smart Chicken Feeder — Mobile & Web Client (`app/`)

Cross-platform **Flutter 3.x (Dart)** client application for the **Smart Mobile-Based Solar-Powered Chicken Feeding System with Automated Dispensing and Real-Time Alerts**.

## Directory Structure

```text
app/
├── android/                        # Android Gradle (Kotlin DSL) & AndroidManifest.xml
├── assets/images/app_logo.png      # Branded Rooster application emblem
├── ios/                            # iOS Runner Xcode project & Info.plist
├── lib/
│   ├── main.dart                   # App bootstrap, Firebase Auth/RTDB init & 4-tab shell
│   ├── firebase_options.dart       # [GIT-IGNORED] Private local Firebase platform keys
│   ├── models/
│   │   ├── feeder_command.dart     # FeederCommand, FeederAction & CommandStatus enums
│   │   ├── feeding_log.dart        # FeedingLog model, accuracy math & CSV row builder
│   │   ├── schedule.dart           # FeedingSchedule model & 12h time formatter
│   │   └── telemetry.dart          # FeederTelemetry & 3-minute heartbeat isOnline check
│   ├── screens/
│   │   ├── dashboard_screen.dart   # Live hopper/solar/battery gauges, manual feed & fault clear
│   │   ├── diagnostics_screen.dart # 2-point HX711 calibration & MG996R servo sweep
│   │   ├── history_screen.dart     # Chapter IV empirical metrics & UTF-8 BOM CSV export
│   │   ├── onboarding_screen.dart  # 4-slide first-run operator walkthrough
│   │   ├── schedules_screen.dart   # Daily schedule CRUD, test-run & 4-second undo
│   │   └── settings_screen.dart    # Theme, Cloud/SoftAP switch, Wi-Fi provisioning & alerts
│   ├── services/
│   │   ├── alert_notification_service.dart # Local OS notifications, cooldown & hysteresis
│   │   ├── feeder_service.dart     # Central ChangeNotifier state engine & offline cache
│   │   ├── settings_service.dart   # Persistent operator preferences
│   │   ├── file_export/            # Cross-platform CSV downloader (IO & Web)
│   │   └── hardware/
│   │       ├── hardware_adapter.dart          # Abstract transport strategy contract
│   │       ├── firebase_hardware_adapter.dart # Firebase RTDB native stream + REST client
│   │       └── rest_hardware_adapter.dart     # Direct SoftAP HTTP client (192.168.4.1)
│   ├── theme/app_theme.dart        # Liquid Glass Dark Forest & Light theme tokens
│   └── widgets/                    # ConnectionBanner, HardwareGuideDialog, AppLogo, Skeleton
├── test/
│   ├── widget_test.dart            # Model, service, UI & loopback socket unit tests
│   ├── integration_audit_test.dart # End-to-end safety, alert & persistence audit tests
│   └── mocks/mock_hardware_adapter.dart # Test-only simulator
├── web/                            # PWA manifest.json, icons & index.html
└── pubspec.yaml                    # Flutter dependencies & asset configuration
```

## Build & Verification Commands

```powershell
# 1. Fetch dependencies
flutter pub get

# 2. Static analysis (0 issues required)
dart analyze lib/ test/

# 3. Run all 26 automated unit & integration tests
flutter test --no-pub --timeout 30s

# 4. Build Split-ABI Release Android APKs
flutter build apk --release --split-per-abi

# 5. Build Progressive Web App (PWA) for Firebase Hosting (iOS / Web)
flutter build web --release
```
