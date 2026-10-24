import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
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
  Timer? _scheduleWatchTimer;
  final Set<String> _executedScheduleMinutes = {};
  bool _isDispensing = false;

  FeederConnection _connection = FeederConnection.offline;
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

  /// Optional injected adapter (defaults to MockHardwareAdapter with offline default for pre-fabrication testing).
  FeederService({
    FeederHardwareAdapter? adapter,
    Duration connectDelay = const Duration(milliseconds: 600),
    bool simulateOffline = true,
  }) : _adapter = adapter ?? MockHardwareAdapter(connectDelay: connectDelay, simulateOffline: simulateOffline) {
    if (!simulateOffline) {
      _connection = FeederConnection.online;
      _isInitialLoading = false;
      _lastSyncedAt = DateTime.now();
    }
    _initSampleData();
    _bindAdapter(_adapter);
    _initScheduleWatcher();
  }

  void _bindAdapter(FeederHardwareAdapter adapter) {
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _logSub?.cancel();

    _telemetrySub = adapter.telemetryStream.listen((t) {
      _telemetry = t;
      _isDispensing = t.status == FeederStatus.dispensing;
      if (t.isOnline) {
        _lastSyncedAt = DateTime.now();
      }
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
      if (!_history.any((l) => l.id == log.id)) {
        _history.insert(0, log);
        _syncLogToCloud(log);
        notifyListeners();
      }
    });

    adapter.initialize();
    syncWithFirebaseCloud();
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
        _telemetry = _telemetry.copyWith(clearHeartbeat: true);
      } else {
        _connection = FeederConnection.online;
        _telemetry = _telemetry.copyWith(lastHeartbeat: DateTime.now());
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

  /// Sends a known weight calibration command to the scale.
  Future<bool> calibrateScale(double knownGrams) async {
    final cmd = FeederCommand(
      id: 'cmd_cal_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.calibrateScale,
      targetGrams: knownGrams,
      timestamp: DateTime.now(),
    );
    final res = await _adapter.sendCommand(cmd);
    return res.status == CommandStatus.completed;
  }

  /// Tests the dispenser servo gate by commanding position [degrees] (0 closed, 90 open).
  Future<bool> testServoGate(int degrees) async {
    final cmd = FeederCommand(
      id: 'cmd_servo_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.dispense,
      durationSeconds: 1,
      targetGrams: degrees.toDouble(),
      timestamp: DateTime.now(),
    );
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

  int get totalDailyDurationSeconds => _schedules
      .where((s) => s.isEnabled)
      .fold<int>(0, (acc, item) => acc + item.durationSeconds);

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

  /// Triggers timed manual feeding on the hardware.
  Future<bool> triggerManualFeed({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (_isDispensing || !isConnected) return false;
    return _adapter.triggerManualDispense(
      durationSeconds: durationSeconds,
      targetGrams: targetGrams,
    );
  }

  /// Triggers execution of a specific scheduled routine on the hardware.
  Future<bool> triggerSchedule(FeedingSchedule schedule) async {
    if (_isDispensing || !isConnected) return false;
    return _adapter.triggerScheduleDispense(schedule);
  }

  void _initScheduleWatcher() {
    _scheduleWatchTimer?.cancel();
    _scheduleWatchTimer = Timer.periodic(const Duration(seconds: 5), (_) => _checkScheduledFeedings());
  }

  void _checkScheduledFeedings() {
    if (_schedules.isEmpty || _isDispensing) return;
    final now = DateTime.now();
    for (final s in _schedules) {
      if (!s.isEnabled) continue;
      if (s.daysOfWeek.isNotEmpty && !s.daysOfWeek.contains(now.weekday)) continue;
      if (s.hour == now.hour && s.minute == now.minute) {
        final key = '${now.year}-${now.month}-${now.day}_${now.hour}:${now.minute}_${s.id}';
        if (!_executedScheduleMinutes.contains(key)) {
          _executedScheduleMinutes.add(key);
          debugPrint('[FeederService] Schedule execution triggered: ${s.label} (${s.timeFormatted})');
          triggerSchedule(s);
        }
      }
    }
  }

  void addSchedule(FeedingSchedule schedule) {
    _schedules.add(schedule);
    _adapter.syncSchedules(_schedules);
    _syncSchedulesToCloud(_schedules);
    notifyListeners();
  }

  void insertScheduleAt(int index, FeedingSchedule schedule) {
    if (index >= 0 && index <= _schedules.length) {
      _schedules.insert(index, schedule);
    } else {
      _schedules.add(schedule);
    }
    _adapter.syncSchedules(_schedules);
    _syncSchedulesToCloud(_schedules);
    notifyListeners();
  }

  void updateSchedule(FeedingSchedule updated) {
    final idx = _schedules.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _schedules[idx] = updated;
      _adapter.syncSchedules(_schedules);
      _syncSchedulesToCloud(_schedules);
      notifyListeners();
    }
  }

  void toggleSchedule(String id, bool enabled) {
    final idx = _schedules.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _schedules[idx] = _schedules[idx].copyWith(isEnabled: enabled);
      _adapter.syncSchedules(_schedules);
      _syncSchedulesToCloud(_schedules);
      notifyListeners();
    }
  }

  void deleteSchedule(String id) {
    _schedules.removeWhere((s) => s.id == id);
    _adapter.syncSchedules(_schedules);
    _syncSchedulesToCloud(_schedules);
    notifyListeners();
  }

  static const String defaultDatabaseUrl =
      'https://smart-chicken-feeder-33bec-default-rtdb.asia-southeast1.firebasedatabase.app';

  /// Synchronizes schedules and history logs directly with Firebase Realtime Database.
  Future<void> syncWithFirebaseCloud() async {
    final hasSched = await refreshSchedulesFromCloud();
    if (!hasSched && _schedules.isNotEmpty) {
      await _syncSchedulesToCloud(_schedules);
    }
    await refreshLogsFromCloud();
  }

  /// Pulls the latest schedules from Firebase RTDB `/schedules.json`.
  Future<bool> refreshSchedulesFromCloud() async {
    try {
      final resp = await http
          .get(Uri.parse('$defaultDatabaseUrl/schedules.json'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200 && resp.body.isNotEmpty && resp.body != 'null') {
        final data = jsonDecode(resp.body);
        final list = <FeedingSchedule>[];
        if (data is Map) {
          for (final entry in data.entries) {
            if (entry.value is Map) {
              list.add(FeedingSchedule.fromMap(entry.key.toString(), entry.value as Map));
            }
          }
        } else if (data is List) {
          for (int i = 0; i < data.length; i++) {
            if (data[i] is Map) {
              final id = data[i]['id']?.toString() ?? 'sch_$i';
              list.add(FeedingSchedule.fromMap(id, data[i] as Map));
            }
          }
        }
        if (list.isNotEmpty) {
          _schedules = list;
          notifyListeners();
          return true;
        }
      }
    } catch (e) {
      debugPrint('refreshSchedulesFromCloud error: $e');
    }
    return false;
  }

  /// Pulls the latest feeding logs from Firebase RTDB `/logs.json`.
  Future<bool> refreshLogsFromCloud() async {
    try {
      final resp = await http
          .get(Uri.parse('$defaultDatabaseUrl/logs.json'))
          .timeout(const Duration(seconds: 4));
      if (resp.statusCode == 200 && resp.body.isNotEmpty && resp.body != 'null') {
        final data = jsonDecode(resp.body);
        if (data is Map) {
          final list = <FeedingLog>[];
          for (final entry in data.entries) {
            if (entry.value is Map) {
              list.add(FeedingLog.fromMap(entry.key.toString(), entry.value as Map));
            }
          }
          if (list.isNotEmpty) {
            list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
            _history = list;
            notifyListeners();
            return true;
          }
        }
      }
    } catch (e) {
      debugPrint('refreshLogsFromCloud error: $e');
    }
    return false;
  }

  Future<void> _syncSchedulesToCloud(List<FeedingSchedule> list) async {
    try {
      final map = {
        for (final s in list)
          s.id: {
            'id': s.id,
            ...s.toMap(),
          },
      };
      await http.put(
        Uri.parse('$defaultDatabaseUrl/schedules.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(map),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Error syncing schedules to Firebase: $e');
    }
  }

  Future<void> _syncLogToCloud(FeedingLog log) async {
    try {
      await http.put(
        Uri.parse('$defaultDatabaseUrl/logs/${log.id}.json'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'id': log.id,
          ...log.toMap(),
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (e) {
      debugPrint('Error syncing log to Firebase: $e');
    }
  }

  String exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln(FeedingLog.csvHeader);
    for (final log in _history) {
      buffer.writeln(log.toCsvRow());
    }
    return buffer.toString();
  }

  /// Exports history logs as native Microsoft Excel SpreadsheetML (.xls),
  /// with bold colored header formatting, typed numeric cells, and PASS/FAIL indicators.
  String exportExcelXml() {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0"?>');
    buffer.writeln('<?mso-application progid="Excel.Sheet"?>');
    buffer.writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet"');
    buffer.writeln(' xmlns:o="urn:schemas-microsoft-com:office:office"');
    buffer.writeln(' xmlns:x="urn:schemas-microsoft-com:office:excel"');
    buffer.writeln(' xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
    buffer.writeln(' <Styles>');
    buffer.writeln('  <Style ss:ID="Header">');
    buffer.writeln('   <Font ss:Bold="1" ss:Color="#FFFFFF"/>');
    buffer.writeln('   <Interior ss:Color="#1B5E20" ss:Pattern="Solid"/>');
    buffer.writeln('   <Alignment ss:Horizontal="Center"/>');
    buffer.writeln('  </Style>');
    buffer.writeln('  <Style ss:ID="Pass">');
    buffer.writeln('   <Font ss:Color="#2E7D32" ss:Bold="1"/>');
    buffer.writeln('   <Alignment ss:Horizontal="Center"/>');
    buffer.writeln('  </Style>');
    buffer.writeln('  <Style ss:ID="Fail">');
    buffer.writeln('   <Font ss:Color="#C62828" ss:Bold="1"/>');
    buffer.writeln('   <Alignment ss:Horizontal="Center"/>');
    buffer.writeln('  </Style>');
    buffer.writeln(' </Styles>');
    buffer.writeln(' <Worksheet ss:Name="Feeding Logs">');
    buffer.writeln('  <Table>');
    buffer.writeln('   <Row ss:StyleID="Header">');
    for (final col in [
      'LogID',
      'Timestamp',
      'TriggerType',
      'TargetWeight_g',
      'ActualWeight_g',
      'Error_g',
      'ErrorPercentage',
      'Duration_sec',
      'HopperLevel_pct',
      'Battery_V',
      'Status'
    ]) {
      buffer.writeln('    <Cell><Data ss:Type="String">$col</Data></Cell>');
    }
    buffer.writeln('   </Row>');
    for (final log in _history) {
      final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp);
      final status = log.isSuccess ? 'PASS' : 'FAIL';
      final statusStyle = log.isSuccess ? 'Pass' : 'Fail';
      buffer.writeln('   <Row>');
      buffer.writeln('    <Cell><Data ss:Type="String">${log.id}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="String">$dateStr</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="String">${log.triggerType}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">${log.targetGrams}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">${log.actualGrams}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">${log.errorGrams.toStringAsFixed(2)}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="String">${log.errorPercentage.toStringAsFixed(2)}%</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">${log.durationSeconds}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">${log.feedLevelPercent}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">${log.batteryVolts}</Data></Cell>');
      buffer.writeln('    <Cell ss:StyleID="$statusStyle"><Data ss:Type="String">$status</Data></Cell>');
      buffer.writeln('   </Row>');
    }
    buffer.writeln('  </Table>');
    buffer.writeln(' </Worksheet>');
    buffer.writeln('</Workbook>');
    return buffer.toString();
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduleWatchTimer?.cancel();
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _logSub?.cancel();
    _adapter.dispose();
    super.dispose();
  }
}
