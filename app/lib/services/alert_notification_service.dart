import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/telemetry.dart';
import '../models/feeding_log.dart';

enum FeederAlertSeverity { info, warning, critical }

@immutable
class FeederAlert {
  final String id;
  final String category;
  final String title;
  final String message;
  final FeederAlertSeverity severity;
  final DateTime timestamp;

  const FeederAlert({
    required this.id,
    required this.category,
    required this.title,
    required this.message,
    required this.severity,
    required this.timestamp,
  });
}

/// Real-time alert evaluation and local OS notification service.
///
/// Enforces strict safety guarantees:
/// - Never emits alerts for unconfirmed placeholder telemetry (`lastHeartbeat == null`).
/// - Latches active conditions (`low_feed`, `low_battery`, `hardware_error`) with
///   hysteresis (+2%) and cooldown windows to prevent duplicate notification spam.
/// - Gracefully degrades to in-app alert stream when OS notification permissions
///   are denied or when running in headless test environments.
class AlertNotificationService {
  final Duration cooldown;
  final bool enableOsNotifications;

  FlutterLocalNotificationsPlugin? _plugin;
  final StreamController<FeederAlert> _alertController = StreamController<FeederAlert>.broadcast();
  final List<FeederAlert> _recentAlerts = [];
  final Set<String> _latchedCategories = <String>{};
  final Map<String, DateTime> _lastFiredAt = <String, DateTime>{};
  final Set<String> _alertedLogIds = <String>{};

  bool _initialized = false;
  bool _osNotificationsAvailable = false;
  bool _disposed = false;
  int _nextNotificationId = 1000;

  AlertNotificationService({
    this.cooldown = const Duration(minutes: 15),
    this.enableOsNotifications = true,
  });

  Stream<FeederAlert> get alertStream => _alertController.stream;
  List<FeederAlert> get recentAlerts => List.unmodifiable(_recentAlerts);
  bool get isOsNotificationsAvailable => _osNotificationsAvailable;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (!enableOsNotifications || kIsWeb) {
      _osNotificationsAvailable = false;
      return;
    }

    try {
      if (defaultTargetPlatform != TargetPlatform.android &&
          defaultTargetPlatform != TargetPlatform.iOS) {
        _osNotificationsAvailable = false;
        return;
      }

      final plugin = FlutterLocalNotificationsPlugin();
      _plugin = plugin;
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(android: androidInit, iOS: iosInit);
      final ok = await plugin.initialize(settings: settings);
      _osNotificationsAvailable = ok ?? false;

      if (defaultTargetPlatform == TargetPlatform.android) {
        await plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      }
    } catch (e) {
      debugPrint('[AlertNotificationService] Native plugin init skipped: $e');
      _osNotificationsAvailable = false;
    }
  }

  /// Evaluates confirmed hardware telemetry against user safety thresholds.
  Future<List<FeederAlert>> evaluateTelemetry(
    FeederTelemetry telemetry, {
    required double lowFeedThreshold,
    required double lowBatteryThreshold,
  }) async {
    // Never alert on unconfirmed cold-start placeholder telemetry
    if (_disposed || telemetry.lastHeartbeat == null || !telemetry.isOnline) {
      return const [];
    }

    final emitted = <FeederAlert>[];

    // 1. Hardware / Sensor Error evaluation
    final hasError = telemetry.status == FeederStatus.error ||
        (telemetry.sensorError != null && telemetry.sensorError!.isNotEmpty);
    if (hasError) {
      final detail = telemetry.sensorError != null
          ? 'Fault code: ${telemetry.sensorError}. Dispenser gate closed safely.'
          : 'Controller reported a hardware or sensor fault. Check scale, hopper sensor, and auger gate.';
      final alert = await _triggerConditionIfEligible(
        category: 'hardware_error',
        title: 'Hardware Safety Fault',
        message: detail,
        severity: FeederAlertSeverity.critical,
      );
      if (alert != null) emitted.add(alert);
    } else {
      _latchedCategories.remove('hardware_error');
    }

    // 2. Low Hopper Feed evaluation (skip if ultrasonic error is active so sensor failure isn't misreported as low feed)
    if (!hasError && telemetry.feedLevelPercent < lowFeedThreshold) {
      final alert = await _triggerConditionIfEligible(
        category: 'low_feed',
        title: 'Low Feed Hopper Warning',
        message:
            'Hopper level is at ${telemetry.feedLevelPercent.toStringAsFixed(0)}% (threshold: ${lowFeedThreshold.toInt()}%). Refill pellets soon.',
        severity: FeederAlertSeverity.warning,
      );
      if (alert != null) emitted.add(alert);
    } else if (telemetry.feedLevelPercent >= lowFeedThreshold + 2.0) {
      _latchedCategories.remove('low_feed');
    }

    // 3. Low Solar Battery evaluation
    if (telemetry.batteryPercent < lowBatteryThreshold || telemetry.batteryVolts < 11.5) {
      final alert = await _triggerConditionIfEligible(
        category: 'low_battery',
        title: 'Low Solar Battery Alert',
        message:
            'Battery at ${telemetry.batteryPercent}% (${telemetry.batteryVolts.toStringAsFixed(2)}V). Check solar charging panel.',
        severity: FeederAlertSeverity.critical,
      );
      if (alert != null) emitted.add(alert);
    } else if (telemetry.batteryPercent >= lowBatteryThreshold + 2.0 &&
        telemetry.batteryVolts >= 11.7) {
      _latchedCategories.remove('low_battery');
    }

    return emitted;
  }

  /// Evaluates newly recorded feeding logs so failed or aborted cycles notify the user once.
  Future<FeederAlert?> evaluateFeedingLog(FeedingLog log) async {
    if (_disposed) return null;
    if (_alertedLogIds.contains(log.id)) return null;
    _alertedLogIds.add(log.id);

    // Ignore historical logs older than 5 minutes loaded during cloud sync
    if (DateTime.now().difference(log.timestamp).inMinutes.abs() > 5) {
      return null;
    }

    if (!log.isSuccess) {
      final alert = FeederAlert(
        id: 'alert_${log.id}',
        category: 'dispense_failed',
        title: 'Feeding Cycle Incomplete',
        message:
            '${log.triggerType} dispensed ${log.actualGrams.toStringAsFixed(1)}g of ${log.targetGrams.toStringAsFixed(0)}g target. Inspect feeder.',
        severity: FeederAlertSeverity.critical,
        timestamp: DateTime.now(),
      );
      await _recordAndDispatch(alert);
      return alert;
    }
    return null;
  }

  /// Recordsexisting log IDs during initial cache/cloud load so historical entries never re-alert.
  void seedHistoricalLogIds(Iterable<String> ids) {
    _alertedLogIds.addAll(ids);
  }

  Future<FeederAlert?> _triggerConditionIfEligible({
    required String category,
    required String title,
    required String message,
    required FeederAlertSeverity severity,
  }) async {
    final now = DateTime.now();
    if (_latchedCategories.contains(category)) {
      final prev = _lastFiredAt[category];
      if (prev != null && now.difference(prev) < cooldown) {
        return null;
      }
    }

    _latchedCategories.add(category);
    _lastFiredAt[category] = now;

    final alert = FeederAlert(
      id: 'alert_${category}_${now.millisecondsSinceEpoch}',
      category: category,
      title: title,
      message: message,
      severity: severity,
      timestamp: now,
    );
    await _recordAndDispatch(alert);
    return alert;
  }

  Future<void> _recordAndDispatch(FeederAlert alert) async {
    if (_disposed) return;
    _recentAlerts.insert(0, alert);
    if (_recentAlerts.length > 50) {
      _recentAlerts.removeRange(50, _recentAlerts.length);
    }
    if (!_alertController.isClosed) {
      _alertController.add(alert);
    }

    if (_osNotificationsAvailable && _plugin != null) {
      try {
        const androidDetails = AndroidNotificationDetails(
          'feeder_safety_alerts',
          'Feeder Safety & Telemetry Alerts',
          channelDescription: 'Real-time alerts for low feed, low solar battery, and dispenser faults',
          importance: Importance.high,
          priority: Priority.high,
        );
        const iosDetails = DarwinNotificationDetails();
        const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
        await _plugin!.show(
          id: _nextNotificationId++,
          title: alert.title,
          body: alert.message,
          notificationDetails: details,
          payload: alert.category,
        );
      } catch (e) {
        debugPrint('[AlertNotificationService] OS notification dispatch error: $e');
      }
    }
  }

  void clearAlerts() {
    _recentAlerts.clear();
    _latchedCategories.clear();
  }

  void dispose() {
    _disposed = true;
    _alertController.close();
  }
}
