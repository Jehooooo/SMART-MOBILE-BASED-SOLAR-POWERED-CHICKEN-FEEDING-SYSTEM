import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/telemetry.dart';
import '../models/schedule.dart';
import '../models/feeding_log.dart';
import '../models/feeder_command.dart';
import 'alert_notification_service.dart';
import 'hardware/firebase_hardware_adapter.dart';
import 'hardware/hardware_adapter.dart';

/// Link state between the mobile app and the cloud database / feeder.
enum FeederConnection { connecting, online, offline }

class FeederService extends ChangeNotifier {
  static const _kSchedulesPrefKey = 'cached_feeder_schedules';
  static const _kLogsPrefKey = 'cached_feeder_logs';
  static const _kInitializedPrefKey = 'feeder_schedules_initialized';

  static const String defaultDatabaseUrl =
      'https://smart-chicken-feeder-33bec-default-rtdb.asia-southeast1.firebasedatabase.app';

  FeederHardwareAdapter _adapter;
  final AlertNotificationService alertService;

  FeederTelemetry _telemetry = FeederTelemetry.initial();
  List<FeedingSchedule> _schedules = [];
  List<FeedingLog> _history = [];
  bool _isDispensing = false;
  bool _isCommandInFlight = false;
  int _scheduleMutationEpoch = 0;

  double _lowFeedThreshold;
  double _lowBatteryThreshold;
  String? _lastErrorMessage;

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
  bool get isCommandInFlight => _isCommandInFlight;

  FeederConnection get connection => _connection;
  bool get isConnected => _connection == FeederConnection.online;

  /// True only when both the transport link is active AND the feeder controller
  /// has reported a live heartbeat within the last 3 minutes (or is in mock mode).
  /// Prevents queuing stale commands in Firebase while the ESP32 is powered off.
  bool get isDeviceOnline => isConnected && (_adapter.isMock || _telemetry.isOnline);

  bool get isInitialLoading => _isInitialLoading;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Latest user-facing error from hardware transport or Firebase sync.
  String? get lastErrorMessage {
    if (_lastErrorMessage != null) return _lastErrorMessage;
    if (_adapter is FirebaseHardwareAdapter) {
      return (_adapter as FirebaseHardwareAdapter).lastErrorMessage;
    }
    return null;
  }

  FeederHardwareAdapter get adapter => _adapter;
  String get hardwareSourceLabel => _adapter.hardwareSourceLabel;
  HardwareTransportType get transportType => _adapter.transportType;
  bool get isMock => _adapter.isMock;

  /// FeederService connects to the physical feeder hardware via Firebase Cloud or Local REST HTTP.
  FeederService({
    FeederHardwareAdapter? adapter,
    AlertNotificationService? alertService,
    double lowFeedThreshold = 20.0,
    double lowBatteryThreshold = 20.0,
    bool enableOsNotifications = true,
  })  : _adapter = adapter ?? FirebaseHardwareAdapter(),
        _lowFeedThreshold = lowFeedThreshold.clamp(5.0, 90.0),
        _lowBatteryThreshold = lowBatteryThreshold.clamp(5.0, 90.0),
        alertService = alertService ?? AlertNotificationService(enableOsNotifications: enableOsNotifications) {
    unawaited(this.alertService.initialize());
    _bindAdapter(_adapter, syncCloudImmediately: false);
    unawaited(_initialLoadSequence());
  }

  Future<void> _initialLoadSequence() async {
    await _loadLocalDataInternal(preserveConcurrentMutations: true);
    if (_disposed) return;
    alertService.seedHistoricalLogIds(_history.map((l) => l.id));
    if (_adapter is FirebaseHardwareAdapter) {
      await syncWithFirebaseCloud();
    }
  }

  /// Updates alert evaluation thresholds from user settings at runtime.
  void updateAlertThresholds({
    required double lowFeedThreshold,
    required double lowBatteryThreshold,
  }) {
    _lowFeedThreshold = lowFeedThreshold;
    _lowBatteryThreshold = lowBatteryThreshold;
    if (_telemetry.isOnline) {
      unawaited(alertService.evaluateTelemetry(
        _telemetry,
        lowFeedThreshold: _lowFeedThreshold,
        lowBatteryThreshold: _lowBatteryThreshold,
      ));
    }
  }

  void _bindAdapter(FeederHardwareAdapter adapter, {bool syncCloudImmediately = true}) {
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
      unawaited(alertService.evaluateTelemetry(
        t,
        lowFeedThreshold: _lowFeedThreshold,
        lowBatteryThreshold: _lowBatteryThreshold,
      ));
      notifyListeners();
    });

    _connectionSub = adapter.connectionStream.listen((c) {
      _connection = c;
      if (c == FeederConnection.online && (adapter.isMock || _telemetry.isOnline)) {
        _lastSyncedAt = DateTime.now();
      }
      _isInitialLoading = false;
      notifyListeners();
    });

    _logSub = adapter.feedingLogStream.listen((log) {
      if (!_history.any((l) => l.id == log.id)) {
        _history.insert(0, log);
        _saveLocalLogs();
        unawaited(alertService.evaluateFeedingLog(log));
        if (adapter is! FirebaseHardwareAdapter) {
          // Logs emitted directly by FirebaseHardwareAdapter already exist in RTDB;
          // only mirror when an external/local adapter emits a fresh record into cloud mode.
        }
        notifyListeners();
      }
    });

    adapter.initialize();
    if (syncCloudImmediately && adapter is FirebaseHardwareAdapter) {
      unawaited(syncWithFirebaseCloud());
    }
  }

  /// Seamlessly switches the hardware communication transport at runtime.
  Future<void> switchAdapter(FeederHardwareAdapter newAdapter) async {
    if (_disposed) return;
    _adapter.dispose();
    _adapter = newAdapter;
    _isDispensing = false;
    _isCommandInFlight = false;
    _lastErrorMessage = null;
    _connection = FeederConnection.connecting;
    _isInitialLoading = true;
    notifyListeners();
    _bindAdapter(_adapter, syncCloudImmediately: true);
  }

  /// Sends a zero/tare calibration command to the scale.
  Future<bool> tareScale() async {
    if (_isDispensing || _isCommandInFlight || !isDeviceOnline) {
      _lastErrorMessage = 'Cannot tare scale while feeder is offline or busy.';
      return false;
    }
    _isCommandInFlight = true;
    try {
      final cmd = FeederCommand.tareScale();
      final res = await _adapter.sendCommand(cmd);
      return res.status == CommandStatus.completed;
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Sends a known weight calibration command to the scale.
  Future<bool> calibrateScale(double knownGrams) async {
    if (_isDispensing || _isCommandInFlight || !isDeviceOnline || knownGrams <= 0) {
      _lastErrorMessage = 'Cannot calibrate scale while feeder is offline or busy.';
      return false;
    }
    _isCommandInFlight = true;
    try {
      final cmd = FeederCommand(
        id: 'cmd_cal_${DateTime.now().millisecondsSinceEpoch}',
        action: FeederAction.calibrateScale,
        targetGrams: knownGrams,
        timestamp: DateTime.now(),
      );
      final res = await _adapter.sendCommand(cmd);
      return res.status == CommandStatus.completed;
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Tests the dispenser servo gate by commanding position [degrees] (0 closed, 90 open)
  /// via dedicated `SERVO_TEST` action (distinct from feed dispensing).
  Future<bool> testServoGate(int degrees) async {
    if (_isDispensing || _isCommandInFlight || !isDeviceOnline) {
      _lastErrorMessage = 'Cannot actuate servo gate while feeder is offline or busy.';
      return false;
    }
    _isCommandInFlight = true;
    try {
      final cmd = FeederCommand.servoTest(degrees.clamp(0, 90));
      final res = await _adapter.sendCommand(cmd);
      return res.status == CommandStatus.completed;
    } finally {
      _isCommandInFlight = false;
    }
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

  /// Attempts to re-establish the connection and verify live controller heartbeat.
  Future<bool> retryConnection() async {
    _connection = FeederConnection.connecting;
    notifyListeners();
    final linkOk = await _adapter.refreshTelemetry();
    return linkOk && isDeviceOnline;
  }

  /// Pulls the latest telemetry from the hardware adapter.
  Future<bool> refreshTelemetry() async {
    final linkOk = await _adapter.refreshTelemetry();
    return linkOk && (_adapter.isMock || _telemetry.isOnline);
  }

  /// Triggers emergency stop on the hardware immediately (always allowed even if command in flight).
  void cancelDispensing() {
    _isDispensing = false;
    notifyListeners();
    _adapter.cancelDispense();
  }

  /// Triggers timed manual feeding on the hardware.
  /// Blocks duplicate rapid taps and blocks queuing commands when the controller is offline.
  Future<bool> triggerManualFeed({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (_isDispensing || _isCommandInFlight || !isDeviceOnline) {
      _lastErrorMessage = !isDeviceOnline
          ? 'Feeder controller is offline. Command not queued.'
          : 'Dispense already in progress.';
      return false;
    }
    if (_telemetry.status == FeederStatus.error) {
      _lastErrorMessage = 'Resolve active hardware/sensor fault before dispensing.';
      return false;
    }

    _isCommandInFlight = true;
    try {
      _lastErrorMessage = null;
      return await _adapter.triggerManualDispense(
        durationSeconds: durationSeconds.clamp(1, 60),
        targetGrams: targetGrams,
      );
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Triggers execution of a specific scheduled routine on the hardware.
  Future<bool> triggerSchedule(FeedingSchedule schedule) async {
    if (_isDispensing || _isCommandInFlight || !isDeviceOnline) {
      _lastErrorMessage = !isDeviceOnline
          ? 'Feeder controller is offline. Schedule test run blocked.'
          : 'Dispense already in progress.';
      return false;
    }
    if (_telemetry.status == FeederStatus.error) {
      _lastErrorMessage = 'Resolve active hardware/sensor fault before dispensing.';
      return false;
    }

    _isCommandInFlight = true;
    try {
      _lastErrorMessage = null;
      return await _adapter.triggerScheduleDispense(schedule);
    } finally {
      _isCommandInFlight = false;
    }
  }

  void addSchedule(FeedingSchedule schedule) {
    _scheduleMutationEpoch++;
    _schedules.add(schedule);
    _saveLocalSchedules();
    unawaited(_syncSchedulesViaAdapter(_schedules));
    notifyListeners();
  }

  void insertScheduleAt(int index, FeedingSchedule schedule) {
    _scheduleMutationEpoch++;
    if (index >= 0 && index <= _schedules.length) {
      _schedules.insert(index, schedule);
    } else {
      _schedules.add(schedule);
    }
    _saveLocalSchedules();
    unawaited(_syncSchedulesViaAdapter(_schedules));
    notifyListeners();
  }

  void updateSchedule(FeedingSchedule updated) {
    final idx = _schedules.indexWhere((s) => s.id == updated.id);
    if (idx != -1) {
      _scheduleMutationEpoch++;
      _schedules[idx] = updated;
      _saveLocalSchedules();
      unawaited(_syncSchedulesViaAdapter(_schedules));
      notifyListeners();
    }
  }

  void toggleSchedule(String id, bool enabled) {
    final idx = _schedules.indexWhere((s) => s.id == id);
    if (idx != -1) {
      _scheduleMutationEpoch++;
      _schedules[idx] = _schedules[idx].copyWith(isEnabled: enabled);
      _saveLocalSchedules();
      unawaited(_syncSchedulesViaAdapter(_schedules));
      notifyListeners();
    }
  }

  void deleteSchedule(String id) {
    _scheduleMutationEpoch++;
    _schedules.removeWhere((s) => s.id == id);
    _saveLocalSchedules();
    unawaited(_syncSchedulesViaAdapter(_schedules));
    notifyListeners();
  }

  Future<bool> _syncSchedulesViaAdapter(List<FeedingSchedule> list) async {
    final ok = await _adapter.syncSchedules(List<FeedingSchedule>.unmodifiable(list));
    if (!ok && !_adapter.isMock) {
      _lastErrorMessage = lastErrorMessage ?? 'Failed to sync schedules to feeder backend.';
      notifyListeners();
    } else if (ok) {
      _lastErrorMessage = null;
    }
    return ok;
  }

  /// Synchronizes schedules and history logs with Firebase Realtime Database
  /// when operating in Firebase Cloud mode.
  Future<void> syncWithFirebaseCloud() async {
    if (_adapter is! FirebaseHardwareAdapter || _disposed) return;
    await refreshSchedulesFromCloud();
    await refreshLogsFromCloud();
  }

  /// Pulls the latest schedules from Firebase RTDB `/schedules.json` when using `FirebaseHardwareAdapter`.
  Future<bool> refreshSchedulesFromCloud() async {
    if (_adapter is! FirebaseHardwareAdapter) {
      // Local/mock mode: reload from local persistence
      await loadLocalData();
      return _adapter.isMock;
    }

    final fb = _adapter as FirebaseHardwareAdapter;
    final remoteList = await fb.fetchSchedulesSnapshot();
    if (remoteList == null) {
      _lastErrorMessage = fb.lastErrorMessage ?? 'Could not sync schedules from Firebase.';
      notifyListeners();
      return false;
    }

    _lastErrorMessage = null;
    if (remoteList.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final isInitialized = prefs.getBool(_kInitializedPrefKey) ?? false;
      if (isInitialized && _schedules.isNotEmpty) {
        return fb.syncSchedules(_schedules);
      } else if (isInitialized && _schedules.isEmpty) {
        return true;
      }
      return false;
    }

    _schedules = remoteList;
    await _saveLocalSchedules();
    notifyListeners();
    return true;
  }

  /// Pulls the latest feeding logs from Firebase RTDB `/logs.json` when using `FirebaseHardwareAdapter`.
  Future<bool> refreshLogsFromCloud() async {
    if (_adapter is! FirebaseHardwareAdapter) {
      await loadLocalData();
      return _adapter.isMock;
    }

    final fb = _adapter as FirebaseHardwareAdapter;
    final remoteLogs = await fb.fetchLogsSnapshot();
    if (remoteLogs == null) {
      _lastErrorMessage = fb.lastErrorMessage ?? 'Could not sync feeding logs from Firebase.';
      notifyListeners();
      return false;
    }

    _lastErrorMessage = null;
    if (remoteLogs.isNotEmpty) {
      alertService.seedHistoricalLogIds(remoteLogs.map((l) => l.id));
      _history = remoteLogs;
      await _saveLocalLogs();
      notifyListeners();
    }
    return true;
  }

  /// Loads cached schedules and logs from SharedPreferences.
  Future<void> loadLocalData() async {
    await _loadLocalDataInternal(preserveConcurrentMutations: false);
  }

  Future<void> _loadLocalDataInternal({required bool preserveConcurrentMutations}) async {
    final startEpoch = _scheduleMutationEpoch;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;

      // 1. Load cached schedules (unless mutated synchronously after constructor start)
      if (!preserveConcurrentMutations || _scheduleMutationEpoch == startEpoch) {
        final isInitialized = prefs.getBool(_kInitializedPrefKey) ?? false;
        final schedJson = prefs.getString(_kSchedulesPrefKey);
        if (schedJson != null && schedJson.isNotEmpty) {
          final List<dynamic> decoded = jsonDecode(schedJson);
          final list = <FeedingSchedule>[];
          for (final item in decoded) {
            if (item is Map) {
              final id = item['id']?.toString() ?? 'sch_${list.length}';
              list.add(FeedingSchedule.fromMap(id, item));
            }
          }
          _schedules = list;
        } else if (isInitialized) {
          _schedules = [];
        }
      }

      // 2. Load cached logs
      final logsJson = prefs.getString(_kLogsPrefKey);
      if (logsJson != null && logsJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(logsJson);
        final list = <FeedingLog>[];
        for (final item in decoded) {
          if (item is Map) {
            final id = item['id']?.toString() ?? 'log_${list.length}';
            list.add(FeedingLog.fromMap(id, item));
          }
        }
        if (list.isNotEmpty) {
          list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          alertService.seedHistoricalLogIds(list.map((l) => l.id));
          _history = list;
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('FeederService.loadLocalData error: $e');
    }
  }

  Future<void> _saveLocalSchedules() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapList = [
        for (final s in _schedules)
          {
            'id': s.id,
            ...s.toMap(),
          }
      ];
      await prefs.setString(_kSchedulesPrefKey, jsonEncode(mapList));
      await prefs.setBool(_kInitializedPrefKey, true);
    } catch (e) {
      debugPrint('Error saving local schedules: $e');
    }
  }

  Future<void> _saveLocalLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mapList = [
        for (final l in _history)
          {
            'id': l.id,
            ...l.toMap(),
          }
      ];
      await prefs.setString(_kLogsPrefKey, jsonEncode(mapList));
    } catch (e) {
      debugPrint('Error saving local logs: $e');
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
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _logSub?.cancel();
    alertService.dispose();
    _adapter.dispose();
    super.dispose();
  }
}
