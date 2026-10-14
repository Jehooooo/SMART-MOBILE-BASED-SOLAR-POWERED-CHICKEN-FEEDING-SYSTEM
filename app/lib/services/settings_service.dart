import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App version shown on the About section. Keep in sync with pubspec.yaml.
const String kAppVersion = '1.0.0';
const String kAppBuild = '1';

/// User preferences saved on the device (theme, feeder name, alert
/// thresholds, onboarding state).
///
/// Persistence is optional: if [SharedPreferences] is null (for example in
/// widget tests), values live only in memory.
class SettingsService extends ChangeNotifier {
  static const _kThemeMode = 'theme_mode';
  static const _kFeederName = 'feeder_name';
  static const _kLowFeedThreshold = 'low_feed_threshold';
  static const _kLowBatteryThreshold = 'low_battery_threshold';
  static const _kHopperCapacityKg = 'hopper_capacity_kg';
  static const _kOnboardingComplete = 'onboarding_complete';

  static const defaultFeederName = 'Coop Feeder #1';
  static const defaultLowFeedThreshold = 20.0;
  static const defaultLowBatteryThreshold = 20.0;
  static const defaultHopperCapacityKg = 5.0;

  final SharedPreferences? _prefs;

  ThemeMode _themeMode;
  String _feederName;
  double _lowFeedThreshold;
  double _lowBatteryThreshold;
  double _hopperCapacityKg;
  bool _onboardingComplete;

  SettingsService({
    SharedPreferences? prefs,
    ThemeMode themeMode = ThemeMode.system,
    String feederName = defaultFeederName,
    double lowFeedThreshold = defaultLowFeedThreshold,
    double lowBatteryThreshold = defaultLowBatteryThreshold,
    double hopperCapacityKg = defaultHopperCapacityKg,
    bool onboardingComplete = false,
  })  : _prefs = prefs,
        _themeMode = themeMode,
        _feederName = feederName,
        _lowFeedThreshold = lowFeedThreshold,
        _lowBatteryThreshold = lowBatteryThreshold,
        _hopperCapacityKg = hopperCapacityKg,
        _onboardingComplete = onboardingComplete;

  /// Loads saved preferences from disk, falling back to defaults.
  static Future<SettingsService> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_kThemeMode) ?? ThemeMode.system.index;
    return SettingsService(
      prefs: prefs,
      themeMode: ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)],
      feederName: prefs.getString(_kFeederName) ?? defaultFeederName,
      lowFeedThreshold: prefs.getDouble(_kLowFeedThreshold) ?? defaultLowFeedThreshold,
      lowBatteryThreshold: prefs.getDouble(_kLowBatteryThreshold) ?? defaultLowBatteryThreshold,
      hopperCapacityKg: prefs.getDouble(_kHopperCapacityKg) ?? defaultHopperCapacityKg,
      onboardingComplete: prefs.getBool(_kOnboardingComplete) ?? false,
    );
  }

  ThemeMode get themeMode => _themeMode;
  String get feederName => _feederName;
  double get lowFeedThreshold => _lowFeedThreshold;
  double get lowBatteryThreshold => _lowBatteryThreshold;
  double get hopperCapacityKg => _hopperCapacityKg;
  bool get onboardingComplete => _onboardingComplete;

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    _prefs?.setInt(_kThemeMode, mode.index);
    notifyListeners();
  }

  void setFeederName(String name) {
    final trimmed = name.trim();
    final value = trimmed.isEmpty ? defaultFeederName : trimmed;
    if (value == _feederName) return;
    _feederName = value;
    _prefs?.setString(_kFeederName, value);
    notifyListeners();
  }

  void setLowFeedThreshold(double value) {
    _lowFeedThreshold = value.clamp(5.0, 50.0);
    _prefs?.setDouble(_kLowFeedThreshold, _lowFeedThreshold);
    notifyListeners();
  }

  void setLowBatteryThreshold(double value) {
    _lowBatteryThreshold = value.clamp(5.0, 50.0);
    _prefs?.setDouble(_kLowBatteryThreshold, _lowBatteryThreshold);
    notifyListeners();
  }

  void setHopperCapacityKg(double value) {
    _hopperCapacityKg = value.clamp(1.0, 50.0);
    _prefs?.setDouble(_kHopperCapacityKg, _hopperCapacityKg);
    notifyListeners();
  }

  void setOnboardingComplete(bool value) {
    _onboardingComplete = value;
    _prefs?.setBool(_kOnboardingComplete, value);
    notifyListeners();
  }

  /// Restores feeder and alert preferences to factory defaults.
  /// Theme and onboarding state are left untouched.
  void resetFeederDefaults() {
    _feederName = defaultFeederName;
    _lowFeedThreshold = defaultLowFeedThreshold;
    _lowBatteryThreshold = defaultLowBatteryThreshold;
    _hopperCapacityKg = defaultHopperCapacityKg;
    _prefs?.setString(_kFeederName, _feederName);
    _prefs?.setDouble(_kLowFeedThreshold, _lowFeedThreshold);
    _prefs?.setDouble(_kLowBatteryThreshold, _lowBatteryThreshold);
    _prefs?.setDouble(_kHopperCapacityKg, _hopperCapacityKg);
    notifyListeners();
  }
}
