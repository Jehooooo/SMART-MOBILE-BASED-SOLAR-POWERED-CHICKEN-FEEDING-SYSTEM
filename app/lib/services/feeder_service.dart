import 'dart:async';
import 'package:flutter/material.dart';
import '../models/telemetry.dart';
import '../models/schedule.dart';
import '../models/feeding_log.dart';

class FeederService extends ChangeNotifier {
  FeederTelemetry _telemetry = FeederTelemetry.initial();
  List<FeedingSchedule> _schedules = [];
  List<FeedingLog> _history = [];
  bool _isDispensing = false;

  FeederTelemetry get telemetry => _telemetry;
  List<FeedingSchedule> get schedules => List.unmodifiable(_schedules);
  List<FeedingLog> get history => List.unmodifiable(_history);
  bool get isDispensing => _isDispensing;

  FeederService() {
    _initSampleData();
  }

  void _initSampleData() {
    // Standard default poultry feeding times (Morning, Mid-day, Afternoon)
    _schedules = [
      const FeedingSchedule(
        id: 'sch_1',
        label: 'Morning Feeding',
        hour: 6,
        minute: 30,
        targetGrams: 180.0,
        isEnabled: true,
      ),
      const FeedingSchedule(
        id: 'sch_2',
        label: 'Midday Feeding',
        hour: 12,
        minute: 0,
        targetGrams: 150.0,
        isEnabled: true,
      ),
      const FeedingSchedule(
        id: 'sch_3',
        label: 'Afternoon Feeding',
        hour: 17,
        minute: 30,
        targetGrams: 200.0,
        isEnabled: true,
      ),
    ];

    // Realistic baseline history for testing Chapter IV analytics
    final now = DateTime.now();
    _history = [
      FeedingLog(
        id: 'log_101',
        timestamp: now.subtract(const Duration(hours: 4)),
        targetGrams: 180.0,
        actualGrams: 181.4,
        durationSeconds: 12,
        triggerType: 'Schedule',
        isSuccess: true,
        batteryVolts: 12.6,
        feedLevelPercent: 78.0,
      ),
      FeedingLog(
        id: 'log_102',
        timestamp: now.subtract(const Duration(hours: 9)),
        targetGrams: 150.0,
        actualGrams: 149.2,
        durationSeconds: 10,
        triggerType: 'Schedule',
        isSuccess: true,
        batteryVolts: 12.7,
        feedLevelPercent: 84.0,
      ),
      FeedingLog(
        id: 'log_103',
        timestamp: now.subtract(const Duration(hours: 22)),
        targetGrams: 200.0,
        actualGrams: 198.8,
        durationSeconds: 14,
        triggerType: 'Schedule',
        isSuccess: true,
        batteryVolts: 12.4,
        feedLevelPercent: 91.0,
      ),
      FeedingLog(
        id: 'log_104',
        timestamp: now.subtract(const Duration(days: 1, hours: 5)),
        targetGrams: 100.0,
        actualGrams: 101.1,
        durationSeconds: 8,
        triggerType: 'Manual',
        isSuccess: true,
        batteryVolts: 12.5,
        feedLevelPercent: 95.0,
      ),
    ];
  }

  FeedingSchedule? get nextSchedule {
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;

    final enabled = _schedules.where((s) => s.isEnabled).toList();
    if (enabled.isEmpty) return null;

    // Sort by time
    enabled.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

    for (final s in enabled) {
      if ((s.hour * 60 + s.minute) > nowMinutes) {
        return s;
      }
    }
    // Otherwise it's the first schedule tomorrow
    return enabled.first;
  }

  Future<bool> triggerManualFeed(double targetGrams) async {
    if (_isDispensing) return false;

    _isDispensing = true;
    _telemetry = FeederTelemetry(
      feedLevelPercent: _telemetry.feedLevelPercent,
      batteryVolts: _telemetry.batteryVolts,
      batteryPercent: _telemetry.batteryPercent,
      currentWeightGrams: 0.0,
      status: FeederStatus.dispensing,
      lastHeartbeat: DateTime.now(),
      lastFedTimestamp: _telemetry.lastFedTimestamp,
      lastFedGrams: _telemetry.lastFedGrams,
      isSolarCharging: _telemetry.isSolarCharging,
    );
    notifyListeners();

    // Simulate weight building up as servo dispenses
    for (int i = 1; i <= 5; i++) {
      await Future.delayed(const Duration(milliseconds: 600));
      final progressWeight = (targetGrams / 5) * i;
      _telemetry = FeederTelemetry(
        feedLevelPercent: _telemetry.feedLevelPercent,
        batteryVolts: _telemetry.batteryVolts,
        batteryPercent: _telemetry.batteryPercent,
        currentWeightGrams: progressWeight,
        status: FeederStatus.dispensing,
        lastHeartbeat: DateTime.now(),
        lastFedTimestamp: _telemetry.lastFedTimestamp,
        lastFedGrams: _telemetry.lastFedGrams,
        isSolarCharging: _telemetry.isSolarCharging,
      );
      notifyListeners();
    }

    final variance = (DateTime.now().millisecond % 5 - 2) * 0.4;
    final actualGrams = (targetGrams + variance).clamp(0.0, 1000.0);
    final newFeedLevel = (_telemetry.feedLevelPercent - (targetGrams / 20.0)).clamp(0.0, 100.0);

    final newLog = FeedingLog(
      id: 'log_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      targetGrams: targetGrams,
      actualGrams: double.parse(actualGrams.toStringAsFixed(1)),
      durationSeconds: 3,
      triggerType: 'Manual',
      isSuccess: true,
      batteryVolts: _telemetry.batteryVolts,
      feedLevelPercent: newFeedLevel,
    );

    _history.insert(0, newLog);
    _isDispensing = false;

    _telemetry = FeederTelemetry(
      feedLevelPercent: newFeedLevel,
      batteryVolts: _telemetry.batteryVolts,
      batteryPercent: _telemetry.batteryPercent,
      currentWeightGrams: 0.0,
      status: newFeedLevel < 20 ? FeederStatus.lowFeed : FeederStatus.idle,
      lastHeartbeat: DateTime.now(),
      lastFedTimestamp: DateTime.now(),
      lastFedGrams: actualGrams,
      isSolarCharging: _telemetry.isSolarCharging,
    );

    notifyListeners();
    return true;
  }

  void addSchedule(FeedingSchedule schedule) {
    _schedules.add(schedule);
    notifyListeners();
  }

  void updateSchedule(FeedingSchedule updated) {
    final idx = _schedules.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _schedules[idx] = updated;
      notifyListeners();
    }
  }

  void toggleSchedule(String id, bool enabled) {
    final idx = _schedules.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _schedules[idx] = _schedules[idx].copyWith(isEnabled: enabled);
      notifyListeners();
    }
  }

  void deleteSchedule(String id) {
    _schedules.removeWhere((s) => s.id == id);
    notifyListeners();
  }

  String exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln(FeedingLog.csvHeader);
    for (final log in _history) {
      buffer.writeln(log.toCsvRow());
    }
    return buffer.toString();
  }
}
