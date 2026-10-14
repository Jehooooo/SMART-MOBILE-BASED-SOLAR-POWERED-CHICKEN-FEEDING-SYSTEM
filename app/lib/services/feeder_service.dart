import 'dart:async';
import 'package:flutter/material.dart';
import '../models/telemetry.dart';
import '../models/schedule.dart';
import '../models/feeding_log.dart';
import '../models/feeder_command.dart';
import 'hardware/hardware_adapter.dart';
import 'hardware/mock_hardware_adapter.dart';

/// Link state between the mobile app and the cloud database / feeder.
enum FeederConnection { connecting, online, offline }

class FeederService extends ChangeNotifier {
  FeederHardwareAdapter _adapter;

  FeederTelemetry _telemetry = FeederTelemetry.initial();
  List<FeedingSchedule> _schedules = [];
  List<FeedingLog> _history = [];
  bool _isDispensing = false;

  FeederConnection _connection = FeederConnection.connecting;
  bool _isInitialLoading = true;
  bool _disposed = false;
  DateTime? _lastSyncedAt;

  StreamSubscription<FeederTelemetry>? _telemetrySub;
  StreamSubscription<FeederConnection>? _connectionSub;
  StreamSubscription<FeedingLog>? _logSub;

  FeederTelemetry get telemetry => _telemetry;
  List<FeedingSchedule> get schedules => List.unmodifiable(_schedules);
  List<FeedingLog> get history => List.unmodifiable(_history);
  bool get isDispensing => _isDispensing;

  FeederConnection get connection => _connection;
  bool get isConnected => _connection == FeederConnection.online;
  bool get isInitialLoading => _isInitialLoading;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  FeederHardwareAdapter get adapter => _adapter;
  String get hardwareSourceLabel => _adapter.hardwareSourceLabel;
  HardwareTransportType get transportType => _adapter.transportType;
  bool get isMock => _adapter.isMock;

  /// Checks if the mock adapter currently has simulated offline mode enabled.
  bool get isSimulatingOffline {
    if (_adapter is MockHardwareAdapter) {
      return (_adapter as MockHardwareAdapter).simulateOffline;
    }
    return false;
  }

  /// Checks if the mock adapter has motor jam simulation enabled.
  bool get isSimulatingMotorJam {
    if (_adapter is MockHardwareAdapter) {
      return (_adapter as MockHardwareAdapter).simulateMotorJam;
    }
    return false;
  }

  /// Checks if the mock adapter has sensor error simulation enabled.
  bool get isSimulatingSensorError {
    if (_adapter is MockHardwareAdapter) {
      return (_adapter as MockHardwareAdapter).simulateSensorError;
    }
    return false;
  }

  /// Optional injected adapter (defaults to MockHardwareAdapter for zero-hardware development).
  FeederService({
    FeederHardwareAdapter? adapter,
    Duration connectDelay = const Duration(milliseconds: 600),
  }) : _adapter = adapter ?? MockHardwareAdapter(connectDelay: connectDelay) {
    _initSampleData();
    _bindAdapter(_adapter);
  }

  void _bindAdapter(FeederHardwareAdapter adapter) {
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _logSub?.cancel();

    _telemetrySub = adapter.telemetryStream.listen((t) {
      _telemetry = t;
      _isDispensing = t.status == FeederStatus.dispensing;
      _lastSyncedAt = DateTime.now();
      _isInitialLoading = false;
      notifyListeners();
    });

    _connectionSub = adapter.connectionStream.listen((c) {
      _connection = c;
      if (c == FeederConnection.online) {
        _lastSyncedAt = DateTime.now();
      }
      _isInitialLoading = false;
      notifyListeners();
    });

    _logSub = adapter.feedingLogStream.listen((log) {
      _history.insert(0, log);
      notifyListeners();
    });

    adapter.initialize();
  }

  /// Seamlessly switches the hardware communication transport at runtime.
  Future<void> switchAdapter(FeederHardwareAdapter newAdapter) async {
    if (_disposed) return;
    _adapter.dispose();
    _adapter = newAdapter;
    _connection = FeederConnection.connecting;
    _isInitialLoading = true;
    notifyListeners();
    _bindAdapter(_adapter);
  }

  /// Testing helper: toggles simulated offline in mock mode.
  void setSimulatedOffline(bool value) {
    if (_adapter is MockHardwareAdapter) {
      final mock = _adapter as MockHardwareAdapter;
      mock.simulateOffline = value;
      if (value) {
        _connection = FeederConnection.offline;
      } else {
        mock.refreshTelemetry();
      }
      notifyListeners();
    }
  }

  /// Testing helper: toggles simulated motor jam / auger stall in mock mode.
  void setSimulatedMotorJam(bool value) {
    if (_adapter is MockHardwareAdapter) {
      final mock = _adapter as MockHardwareAdapter;
      mock.simulateMotorJam = value;
      notifyListeners();
    }
  }

  /// Testing helper: toggles simulated ultrasonic / sensor error in mock mode.
  void setSimulatedSensorError(bool value) {
    if (_adapter is MockHardwareAdapter) {
      final mock = _adapter as MockHardwareAdapter;
      mock.simulateSensorError = value;
      mock.refreshTelemetry();
      notifyListeners();
    }
  }

  /// Restores simulated hopper level to 100%.
  void refillHopper() {
    if (_adapter is MockHardwareAdapter) {
      (_adapter as MockHardwareAdapter).refillHopper();
      notifyListeners();
    }
  }

  /// Sends a zero/tare calibration command to the scale.
  Future<bool> tareScale() async {
    final cmd = FeederCommand.tareScale();
    final res = await _adapter.sendCommand(cmd);
    return res.status == CommandStatus.completed;
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

    enabled.sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));

    for (final s in enabled) {
      if ((s.hour * 60 + s.minute) > nowMinutes) {
        return s;
      }
    }
    return enabled.first;
  }

  double get totalDailyTargetGrams => _schedules
      .where((s) => s.isEnabled)
      .fold<double>(0.0, (acc, item) => acc + item.targetGrams);

  int get activeScheduleCount => _schedules.where((s) => s.isEnabled).length;

  /// Attempts to re-establish the connection.
  Future<bool> retryConnection() async {
    _connection = FeederConnection.connecting;
    notifyListeners();
    return _adapter.refreshTelemetry();
  }

  /// Pulls the latest telemetry from the hardware adapter.
  Future<bool> refreshTelemetry() async {
    return _adapter.refreshTelemetry();
  }

  /// Triggers emergency stop on the hardware.
  void cancelDispensing() {
    _adapter.cancelDispense();
  }

  /// Triggers a closed-loop manual feed on the hardware.
  Future<bool> triggerManualFeed(double targetGrams) async {
    if (_isDispensing || !isConnected) return false;
    return _adapter.triggerManualDispense(targetGrams);
  }

  void addSchedule(FeedingSchedule schedule) {
    _schedules.add(schedule);
    _adapter.syncSchedules(_schedules);
    notifyListeners();
  }

  void insertScheduleAt(int index, FeedingSchedule schedule) {
    if (index >= 0 && index <= _schedules.length) {
      _schedules.insert(index, schedule);
    } else {
      _schedules.add(schedule);
    }
    _adapter.syncSchedules(_schedules);
    notifyListeners();
  }

  void updateSchedule(FeedingSchedule updated) {
    final idx = _schedules.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _schedules[idx] = updated;
      _adapter.syncSchedules(_schedules);
      notifyListeners();
    }
  }

  void toggleSchedule(String id, bool enabled) {
    final idx = _schedules.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _schedules[idx] = _schedules[idx].copyWith(isEnabled: enabled);
      _adapter.syncSchedules(_schedules);
      notifyListeners();
    }
  }

  void deleteSchedule(String id) {
    _schedules.removeWhere((s) => s.id == id);
    _adapter.syncSchedules(_schedules);
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

  @override
  void dispose() {
    _disposed = true;
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _logSub?.cancel();
    _adapter.dispose();
    super.dispose();
  }
}
