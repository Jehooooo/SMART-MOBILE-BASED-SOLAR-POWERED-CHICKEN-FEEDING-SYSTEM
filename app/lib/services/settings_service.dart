// ignore_for_file: prefer_initializing_formals
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'hardware/hardware_adapter.dart';

/// App version shown on the About section. Keep in sync with pubspec.yaml.
const String kAppVersion = '1.0.0';
const String kAppBuild = '1';

/// User preferences saved on the device (theme, feeder name, alert
/// thresholds, onboarding state, hardware transport).
///
/// Cross-platform persistent storage: uses `SharedPreferences` across Web,
/// Windows, Android, and iOS, with optional fallback to `settings.json`.
class SettingsService extends ChangeNotifier {
  static const defaultFeederName = 'Coop Feeder #1';
  static const defaultLowFeedThreshold = 20.0;
  static const defaultLowBatteryThreshold = 20.0;
  static const defaultHopperCapacityKg = 5.0;
  static const defaultHardwareTransport = HardwareTransportType.firebaseCloud;

  static const _fileName = 'smart_feeder_settings.json';

  ThemeMode _themeMode;
  String _feederName;
  double _lowFeedThreshold;
  double _lowBatteryThreshold;
  double _hopperCapacityKg;
  bool _onboardingComplete;
  HardwareTransportType _hardwareTransport;

  SettingsService({
    ThemeMode themeMode = ThemeMode.system,
    String feederName = defaultFeederName,
    double lowFeedThreshold = defaultLowFeedThreshold,
    double lowBatteryThreshold = defaultLowBatteryThreshold,
    double hopperCapacityKg = defaultHopperCapacityKg,
    bool onboardingComplete = false,
    HardwareTransportType hardwareTransport = defaultHardwareTransport,
  })  : _themeMode = themeMode,
        _feederName = feederName,
        _lowFeedThreshold = lowFeedThreshold,
        _lowBatteryThreshold = lowBatteryThreshold,
        _hopperCapacityKg = hopperCapacityKg,
        _onboardingComplete = onboardingComplete,
        _hardwareTransport = hardwareTransport;

  static File? _getStorageFile() {
    if (kIsWeb) return null;
    try {
      return File(_fileName);
    } catch (_) {
      return null;
    }
  }

  /// Loads saved preferences from SharedPreferences, falling back to disk/defaults.
  static Future<SettingsService> load() async {
    final service = SettingsService();
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey('hardware_transport') ||
          prefs.containsKey('theme_mode') ||
          prefs.containsKey('feeder_name')) {
        final themeIdx = prefs.getInt('theme_mode') ?? ThemeMode.system.index;
        service._themeMode = ThemeMode.values[themeIdx.clamp(0, ThemeMode.values.length - 1)];
        service._feederName = prefs.getString('feeder_name') ?? defaultFeederName;
        service._lowFeedThreshold = prefs.getDouble('low_feed_threshold') ?? defaultLowFeedThreshold;
        service._lowBatteryThreshold = prefs.getDouble('low_battery_threshold') ?? defaultLowBatteryThreshold;
        service._hopperCapacityKg = prefs.getDouble('hopper_capacity_kg') ?? defaultHopperCapacityKg;
        service._onboardingComplete = prefs.getBool('onboarding_complete') ?? false;
        final transportIdx = prefs.getInt('hardware_transport') ?? defaultHardwareTransport.index;
        service._hardwareTransport = HardwareTransportType.values[transportIdx.clamp(0, HardwareTransportType.values.length - 1)];
        return service;
      }

      // Legacy file migration fallback
      final file = _getStorageFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final Map<String, dynamic> data = jsonDecode(content);
          final themeIdx = data['theme_mode'] as int? ?? ThemeMode.system.index;
          service._themeMode = ThemeMode.values[themeIdx.clamp(0, ThemeMode.values.length - 1)];
          service._feederName = data['feeder_name'] as String? ?? defaultFeederName;
          service._lowFeedThreshold = (data['low_feed_threshold'] as num?)?.toDouble() ?? defaultLowFeedThreshold;
          service._lowBatteryThreshold = (data['low_battery_threshold'] as num?)?.toDouble() ?? defaultLowBatteryThreshold;
          service._hopperCapacityKg = (data['hopper_capacity_kg'] as num?)?.toDouble() ?? defaultHopperCapacityKg;
          service._onboardingComplete = data['onboarding_complete'] as bool? ?? false;
          final transportIdx = data['hardware_transport'] as int? ?? defaultHardwareTransport.index;
          service._hardwareTransport = HardwareTransportType.values[transportIdx.clamp(0, HardwareTransportType.values.length - 1)];
          // Migrate to SharedPreferences
          await service._save();
        }
      }
    } catch (e) {
      debugPrint('SettingsService.load error, using defaults: $e');
    }
    return service;
  }

  /// Explicitly flushes current settings to persistent storage.
  Future<void> save() => _save();

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('theme_mode', _themeMode.index);
      await prefs.setString('feeder_name', _feederName);
      await prefs.setDouble('low_feed_threshold', _lowFeedThreshold);
      await prefs.setDouble('low_battery_threshold', _lowBatteryThreshold);
      await prefs.setDouble('hopper_capacity_kg', _hopperCapacityKg);
      await prefs.setBool('onboarding_complete', _onboardingComplete);
      await prefs.setInt('hardware_transport', _hardwareTransport.index);

      // Redundant file backup where accessible
      final file = _getStorageFile();
      if (file != null) {
        final map = {
          'theme_mode': _themeMode.index,
          'feeder_name': _feederName,
          'low_feed_threshold': _lowFeedThreshold,
          'low_battery_threshold': _lowBatteryThreshold,
          'hopper_capacity_kg': _hopperCapacityKg,
          'onboarding_complete': _onboardingComplete,
          'hardware_transport': _hardwareTransport.index,
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
  HardwareTransportType get hardwareTransport => _hardwareTransport;

  Future<void> setHardwareTransport(HardwareTransportType transport) async {
    _hardwareTransport = transport;
    await _save();
    notifyListeners();
  }

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
