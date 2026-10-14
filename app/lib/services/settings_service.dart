// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// App version shown on the About section. Keep in sync with pubspec.yaml.
const String kAppVersion = '1.0.0';
const String kAppBuild = '1';

/// User preferences saved on the device (theme, feeder name, alert
/// thresholds, onboarding state).
///
/// Pure Dart JSON persistence: uses `settings.json` locally when file system
/// is available (Windows / Android), and gracefully falls back to in-memory
/// for Flutter Web or automated test runners without needing external packages.
class SettingsService extends ChangeNotifier {
  static const defaultFeederName = 'Coop Feeder #1';
  static const defaultLowFeedThreshold = 20.0;
  static const defaultLowBatteryThreshold = 20.0;
  static const defaultHopperCapacityKg = 5.0;

  static const _fileName = 'smart_feeder_settings.json';

  ThemeMode _themeMode;
  String _feederName;
  double _lowFeedThreshold;
  double _lowBatteryThreshold;
  double _hopperCapacityKg;
  bool _onboardingComplete;

  SettingsService({
    ThemeMode themeMode = ThemeMode.system,
    String feederName = defaultFeederName,
    double lowFeedThreshold = defaultLowFeedThreshold,
    double lowBatteryThreshold = defaultLowBatteryThreshold,
    double hopperCapacityKg = defaultHopperCapacityKg,
    bool onboardingComplete = false,
  })  : _themeMode = themeMode,
        _feederName = feederName,
        _lowFeedThreshold = lowFeedThreshold,
        _lowBatteryThreshold = lowBatteryThreshold,
        _hopperCapacityKg = hopperCapacityKg,
        _onboardingComplete = onboardingComplete;

  static File? _getStorageFile() {
    if (kIsWeb) return null;
    try {
      return File(_fileName);
    } catch (_) {
      return null;
    }
  }

  /// Loads saved preferences from disk, falling back to defaults.
  static Future<SettingsService> load() async {
    final service = SettingsService();
    try {
      final file = _getStorageFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        final themeIdx = data['theme_mode'] as int? ?? ThemeMode.system.index;
        service._themeMode = ThemeMode.values[themeIdx.clamp(0, ThemeMode.values.length - 1)];
        service._feederName = data['feeder_name'] as String? ?? defaultFeederName;
        service._lowFeedThreshold = (data['low_feed_threshold'] as num?)?.toDouble() ?? defaultLowFeedThreshold;
        service._lowBatteryThreshold = (data['low_battery_threshold'] as num?)?.toDouble() ?? defaultLowBatteryThreshold;
        service._hopperCapacityKg = (data['hopper_capacity_kg'] as num?)?.toDouble() ?? defaultHopperCapacityKg;
        service._onboardingComplete = data['onboarding_complete'] as bool? ?? false;
      }
    } catch (e) {
      debugPrint('SettingsService.load fallback to memory: $e');
    }
    return service;
  }

  Future<void> _save() async {
    try {
      final file = _getStorageFile();
      if (file != null) {
        final map = {
          'theme_mode': _themeMode.index,
          'feeder_name': _feederName,
          'low_feed_threshold': _lowFeedThreshold,
          'low_battery_threshold': _lowBatteryThreshold,
          'hopper_capacity_kg': _hopperCapacityKg,
          'onboarding_complete': _onboardingComplete,
        };
        await file.writeAsString(jsonEncode(map));
      }
    } catch (e) {
      debugPrint('SettingsService._save error: $e');
    }
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
    _save();
    notifyListeners();
  }

  void setFeederName(String name) {
    final trimmed = name.trim();
    final value = trimmed.isEmpty ? defaultFeederName : trimmed;
    if (value == _feederName) return;
    _feederName = value;
    _save();
    notifyListeners();
  }

  void setLowFeedThreshold(double value) {
    _lowFeedThreshold = value.clamp(5.0, 50.0);
    _save();
    notifyListeners();
  }

  void setLowBatteryThreshold(double value) {
    _lowBatteryThreshold = value.clamp(5.0, 50.0);
    _save();
    notifyListeners();
  }

  void setHopperCapacityKg(double value) {
    _hopperCapacityKg = value.clamp(1.0, 50.0);
    _save();
    notifyListeners();
  }

  void setOnboardingComplete(bool value) {
    _onboardingComplete = value;
    _save();
    notifyListeners();
  }

  /// Restores feeder and alert preferences to factory defaults.
  /// Theme and onboarding state are left untouched.
  void resetFeederDefaults() {
    _feederName = defaultFeederName;
    _lowFeedThreshold = defaultLowFeedThreshold;
    _lowBatteryThreshold = defaultLowBatteryThreshold;
    _hopperCapacityKg = defaultHopperCapacityKg;
    _save();
    notifyListeners();
  }
}
