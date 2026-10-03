# Smart Mobile-Based Solar-Powered Chicken Feeding System

Automated, solar-powered poultry feeder with weight-based dispensing and real-time mobile alerts.

## Repository layout

| Path | Contents |
|---|---|
| `firmware/` | ESP32 firmware (PlatformIO, Arduino framework) |
| `app/` | Flutter mobile app (Android) |
| `docs/` | Methodology analysis, wiring, test data |

## Setup

### Firmware
```powershell
uv tool install platformio          # one-time
cd firmware
copy include\secrets.example.h include\secrets.h   # fill Wi-Fi / Firebase
pio run                              # build
pio run -t upload; pio device monitor
```

### Mobile app
```powershell
# Flutter SDK installed at C:\Users\Jeho\dev\flutter (on user PATH)
cd app
flutter pub get
flutter run
```
Firebase config files (`google-services.json`, `firebase_options.dart`) are git-ignored — generate them with `flutterfire configure`.

See [docs/methodology_analysis.md](docs/methodology_analysis.md) for requirements and design notes.
