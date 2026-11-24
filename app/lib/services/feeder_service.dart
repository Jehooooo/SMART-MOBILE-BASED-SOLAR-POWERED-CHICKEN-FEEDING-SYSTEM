import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/telemetry.dart';
import '../models/schedule.dart';
import '../models/feeding_log.dart';
import '../models/feeder_command.dart';
import '../utils/feed_portions.dart';
import 'alert_notification_service.dart';
import 'hardware/firebase_hardware_adapter.dart';
import 'hardware/hardware_adapter.dart';
import 'hardware/rest_hardware_adapter.dart';

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

  // Frontend-only Offline Simulation / Test Mode state (never persisted or sent to hardware/Firebase)
  bool _isOfflineSimulationMode = false;
  Timer? _simDispenseTimer;
  int? _simDispenseDurationSec;
  String? _simDispenseTriggerType;
  FeederTelemetry? _savedRealTelemetry;
  List<FeedingSchedule>? _savedRealSchedules;
  List<FeedingLog>? _savedRealHistory;
  FeederConnection? _savedRealConnection;
  String? _savedRealError;
  DateTime? _savedRealSyncedAt;
  bool _savedRealInitialLoading = false;

  StreamSubscription<FeederTelemetry>? _telemetrySub;
  StreamSubscription<FeederConnection>? _connectionSub;
  StreamSubscription<FeedingLog>? _logSub;

  FeederTelemetry get telemetry => _telemetry;
  List<FeedingSchedule> get schedules => List.unmodifiable(_schedules);
  List<FeedingLog> get history => List.unmodifiable(_history);
  bool get isDispensing => _isDispensing;
  bool get isCommandInFlight => _isCommandInFlight;
  bool get isOfflineSimulationMode => _isOfflineSimulationMode;

  FeederConnection get connection => _isOfflineSimulationMode ? FeederConnection.online : _connection;
  bool get isConnected => _isOfflineSimulationMode || _connection == FeederConnection.online;

  /// True only when both the transport link is active AND the feeder controller
  /// has reported a live heartbeat within the last 3 minutes (or is in mock/simulation mode).
  /// Prevents queuing stale commands in Firebase while the ESP32 is powered off.
  bool get isDeviceOnline =>
      _isOfflineSimulationMode || (isConnected && (_adapter.isMock || _telemetry.isOnline));

  bool get isInitialLoading => _isOfflineSimulationMode ? false : _isInitialLoading;
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Latest user-facing error from hardware transport or Firebase sync.
  String? get lastErrorMessage {
    if (_isOfflineSimulationMode) return _lastErrorMessage;
    if (_lastErrorMessage != null) return _lastErrorMessage;
    if (_adapter is FirebaseHardwareAdapter) {
      return (_adapter as FirebaseHardwareAdapter).lastErrorMessage;
    }
    return null;
  }

  FeederHardwareAdapter get adapter => _adapter;
  String get hardwareSourceLabel => _isOfflineSimulationMode
      ? 'Offline Simulation Mode (Local UI Preview)'
      : _adapter.hardwareSourceLabel;
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
    if (_adapter is FirebaseHardwareAdapter || _adapter is RestHardwareAdapter) {
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
      if (_isOfflineSimulationMode) {
        _savedRealTelemetry = t;
        if (t.isOnline) _savedRealSyncedAt = DateTime.now();
        _savedRealInitialLoading = false;
        return;
      }
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
      if (_isOfflineSimulationMode) {
        _savedRealConnection = c;
        if (c == FeederConnection.online && (adapter.isMock || (_savedRealTelemetry?.isOnline ?? false))) {
          _savedRealSyncedAt = DateTime.now();
        }
        _savedRealInitialLoading = false;
        return;
      }
      _connection = c;
      if (c == FeederConnection.online && (adapter.isMock || _telemetry.isOnline)) {
        _lastSyncedAt = DateTime.now();
      }
      _isInitialLoading = false;
      notifyListeners();
    });

    _logSub = adapter.feedingLogStream.listen((log) {
      if (_isOfflineSimulationMode) {
        final saved = _savedRealHistory;
        if (saved != null && !saved.any((l) => l.id == log.id)) {
          saved.insert(0, log);
        }
        return;
      }
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
    if (syncCloudImmediately &&
        (adapter is FirebaseHardwareAdapter || adapter is RestHardwareAdapter)) {
      unawaited(syncWithFirebaseCloud());
    }
  }

  /// Toggles frontend-only Offline Simulation / Test Mode so the operator can preview
  /// UI changes, kg/g calibration, manual dispensing, schedules, logs, and notifications
  /// offline without sending commands to the ESP32 or modifying Firebase/local saved data.
  void setOfflineSimulationMode(bool enabled) {
    if (_disposed || enabled == _isOfflineSimulationMode) return;

    if (enabled) {
      _savedRealTelemetry = _telemetry;
      _savedRealSchedules = List<FeedingSchedule>.from(_schedules);
      _savedRealHistory = List<FeedingLog>.from(_history);
      _savedRealConnection = _connection;
      _savedRealError = _lastErrorMessage;
      _savedRealSyncedAt = _lastSyncedAt;
      _savedRealInitialLoading = _isInitialLoading;

      final now = DateTime.now();
      _isOfflineSimulationMode = true;
      _isDispensing = false;
      _isCommandInFlight = false;
      _lastErrorMessage = null;
      _lastSyncedAt = now;

      _telemetry = FeederTelemetry(
        feedLevelPercent: 84.0,
        batteryVolts: 12.6,
        batteryPercent: 90,
        currentWeightGrams: 0.0,
        status: FeederStatus.idle,
        lastHeartbeat: now,
        lastFedTimestamp: now.subtract(const Duration(minutes: 25)),
        lastFedGrams: FeedPortions.gramsForDuration(5),
        isSolarCharging: now.hour >= 6 && now.hour < 18,
      );

      _schedules = _savedRealSchedules!.isNotEmpty
          ? List<FeedingSchedule>.from(_savedRealSchedules!)
          : [
              const FeedingSchedule(
                id: 'sim_sch_1',
                label: 'Morning Feeding',
                hour: 6,
                minute: 30,
                durationSeconds: 3,
                targetGrams: 60.0,
              ),
              const FeedingSchedule(
                id: 'sim_sch_2',
                label: 'Midday Feeding',
                hour: 12,
                minute: 0,
                durationSeconds: 5,
                targetGrams: 100.0,
              ),
              const FeedingSchedule(
                id: 'sim_sch_3',
                label: 'Evening Snack',
                hour: 17,
                minute: 30,
                durationSeconds: 1,
                targetGrams: 20.0,
              ),
            ];

      final simLogs = [
        FeedingLog(
          id: 'sim_seed_5s',
          timestamp: now.subtract(const Duration(minutes: 25)),
          targetGrams: FeedPortions.gramsForDuration(5),
          actualGrams: FeedPortions.gramsForDuration(5),
          durationSeconds: 5,
          triggerType: 'Manual',
          isSuccess: true,
          batteryVolts: 12.6,
          feedLevelPercent: 84.0,
        ),
        FeedingLog(
          id: 'sim_seed_4s',
          timestamp: now.subtract(const Duration(minutes: 55)),
          targetGrams: FeedPortions.gramsForDuration(4),
          actualGrams: FeedPortions.gramsForDuration(4),
          durationSeconds: 4,
          triggerType: 'Manual',
          isSuccess: true,
          batteryVolts: 12.6,
          feedLevelPercent: 87.0,
        ),
        FeedingLog(
          id: 'sim_seed_3s',
          timestamp: now.subtract(const Duration(hours: 2)),
          targetGrams: FeedPortions.gramsForDuration(3),
          actualGrams: FeedPortions.gramsForDuration(3),
          durationSeconds: 3,
          triggerType: 'Schedule (Midday Feeding)',
          isSuccess: true,
          batteryVolts: 12.7,
          feedLevelPercent: 90.0,
        ),
        FeedingLog(
          id: 'sim_seed_2s',
          timestamp: now.subtract(const Duration(hours: 3, minutes: 30)),
          targetGrams: FeedPortions.gramsForDuration(2),
          actualGrams: FeedPortions.gramsForDuration(2),
          durationSeconds: 2,
          triggerType: 'Manual',
          isSuccess: true,
          batteryVolts: 12.6,
          feedLevelPercent: 93.0,
        ),
        FeedingLog(
          id: 'sim_seed_1s',
          timestamp: now.subtract(const Duration(hours: 5)),
          targetGrams: FeedPortions.gramsForDuration(1),
          actualGrams: FeedPortions.gramsForDuration(1),
          durationSeconds: 1,
          triggerType: 'Schedule (Morning Feeding)',
          isSuccess: true,
          batteryVolts: 12.5,
          feedLevelPercent: 96.0,
        ),
      ];
      alertService.seedHistoricalLogIds(simLogs.map((l) => l.id));
      _history = simLogs;
      notifyListeners();
    } else {
      _simDispenseTimer?.cancel();
      _simDispenseTimer = null;
      _simDispenseDurationSec = null;
      _simDispenseTriggerType = null;

      _isOfflineSimulationMode = false;
      _isDispensing = false;
      _isCommandInFlight = false;
      _telemetry = _savedRealTelemetry ?? FeederTelemetry.initial();
      _schedules = _savedRealSchedules ?? [];
      _history = _savedRealHistory ?? [];
      _connection = _savedRealConnection ?? FeederConnection.offline;
      _lastErrorMessage = _savedRealError;
      _lastSyncedAt = _savedRealSyncedAt;
      _isInitialLoading = _savedRealInitialLoading;

      _savedRealTelemetry = null;
      _savedRealSchedules = null;
      _savedRealHistory = null;
      _savedRealConnection = null;
      _savedRealError = null;
      _savedRealSyncedAt = null;
      notifyListeners();
    }
  }

  Future<bool> _runSimulatedDispense({
    required int durationSeconds,
    required String triggerType,
    required String triggerLabel,
    Duration simulationDuration = const Duration(milliseconds: 1800),
  }) async {
    if (_isDispensing || _isCommandInFlight) return false;
    final clampedSec = durationSeconds.clamp(1, 60);
    final portionGrams = FeedPortions.gramsForDuration(clampedSec);

    _lastErrorMessage = null;
    _isDispensing = true;
    _simDispenseDurationSec = clampedSec;
    _simDispenseTriggerType = triggerType;
    _telemetry = _telemetry.copyWith(
      status: FeederStatus.dispensing,
      lastHeartbeat: DateTime.now(),
    );
    notifyListeners();

    unawaited(alertService.notifyDispenseTriggered(
      durationSeconds: clampedSec,
      targetGrams: portionGrams,
      triggerLabel: triggerLabel,
    ));

    _simDispenseTimer?.cancel();
    _simDispenseTimer = Timer(simulationDuration, () {
      if (_disposed || !_isOfflineSimulationMode || !_isDispensing) return;
      final now = DateTime.now();
      final log = FeedingLog(
        id: 'sim_log_${now.millisecondsSinceEpoch}',
        timestamp: now,
        targetGrams: portionGrams,
        actualGrams: portionGrams,
        durationSeconds: clampedSec,
        triggerType: triggerType,
        isSuccess: true,
        batteryVolts: _telemetry.batteryVolts,
        feedLevelPercent: _telemetry.feedLevelPercent,
      );
      _history.insert(0, log);
      _isDispensing = false;
      _simDispenseDurationSec = null;
      _simDispenseTriggerType = null;
      _telemetry = _telemetry.copyWith(
        status: FeederStatus.idle,
        lastHeartbeat: now,
        lastFedTimestamp: now,
        lastFedGrams: portionGrams,
      );
      unawaited(alertService.evaluateFeedingLog(log));
      notifyListeners();
    });
    return true;
  }

  /// Seamlessly switches the hardware communication transport at runtime.
  Future<void> switchAdapter(FeederHardwareAdapter newAdapter) async {
    if (_disposed) return;
    if (_isOfflineSimulationMode) {
      setOfflineSimulationMode(false);
    }
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
    if (_isOfflineSimulationMode) {
      if (_isDispensing) return false;
      _telemetry = _telemetry.copyWith(
        currentWeightGrams: 0.0,
        lastHeartbeat: DateTime.now(),
      );
      notifyListeners();
      return true;
    }
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

  /// Clears transient dispense/sensor faults (e.g. dispense timeout or empty-hopper stall)
  /// and re-polls live telemetry. Works across both Cloud (even if ESP32 is offline) and SoftAP.
  Future<bool> clearHardwareFault() async {
    if (_isOfflineSimulationMode) {
      _telemetry = _telemetry.copyWith(
        status: FeederStatus.idle,
        clearSensorError: true,
        lastHeartbeat: DateTime.now(),
      );
      _lastErrorMessage = null;
      notifyListeners();
      return true;
    }
    if (_isDispensing || _isCommandInFlight || (!isConnected && !isDeviceOnline)) {
      _lastErrorMessage = 'Cannot clear fault while feeder is offline or busy.';
      return false;
    }
    _isCommandInFlight = true;
    try {
      bool cmdOk = false;
      if (_adapter is RestHardwareAdapter) {
        cmdOk = await (_adapter as RestHardwareAdapter).clearFault();
      } else if (_adapter is FirebaseHardwareAdapter) {
        cmdOk = await (_adapter as FirebaseHardwareAdapter).clearFault(
          sendDeviceCommand: isDeviceOnline,
        );
      } else {
        final res = await _adapter.sendCommand(FeederCommand.clearFault());
        cmdOk = res.status == CommandStatus.completed;
      }
      await _adapter.refreshTelemetry();
      await Future<void>.delayed(Duration.zero);
      final faultCleared = _telemetry.status != FeederStatus.error &&
          (_telemetry.sensorError == null || _telemetry.sensorError!.isEmpty);
      if (cmdOk && !faultCleared && _adapter is! RestHardwareAdapter) {
        _telemetry = _telemetry.copyWith(
          status: FeederStatus.idle,
          clearSensorError: true,
        );
        _lastErrorMessage = null;
        notifyListeners();
        return true;
      }
      if (faultCleared) {
        _lastErrorMessage = null;
      }
      return cmdOk && faultCleared;
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Sends a known weight calibration command to the scale.
  Future<bool> calibrateScale(double knownGrams) async {
    if (_isOfflineSimulationMode) {
      if (_isDispensing || knownGrams <= 0) return false;
      _telemetry = _telemetry.copyWith(
        currentWeightGrams: knownGrams,
        lastHeartbeat: DateTime.now(),
      );
      notifyListeners();
      return true;
    }
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

  /// Tests the dispenser servo gate by commanding position [degrees] (0 left/closed, 90 middle, 180 full open)
  /// via dedicated `SERVO_TEST` action (distinct from feed dispensing).
  Future<bool> testServoGate(int degrees) async {
    if (_isOfflineSimulationMode) {
      return !_isDispensing;
    }
    if (_isDispensing || _isCommandInFlight || !isDeviceOnline) {
      _lastErrorMessage = 'Cannot actuate servo gate while feeder is offline or busy.';
      return false;
    }
    _isCommandInFlight = true;
    try {
      final cmd = FeederCommand.servoTest(degrees.clamp(0, 180));
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
      .fold<double>(
        0.0,
        (acc, item) => acc +
            (item.durationSeconds > 0
                ? FeedPortions.gramsForDuration(item.durationSeconds)
                : item.targetGrams),
      );

  /// Formatted daily target range across enabled schedules (e.g., `3.25kg - 4.2kg`).
  String get totalDailyTargetRangeLabel {
    var minSum = 0.0;
    var maxSum = 0.0;
    for (final s in _schedules.where((s) => s.isEnabled)) {
      if (s.durationSeconds > 0) {
        final (minG, maxG) = FeedPortions.rangeGramsForDuration(s.durationSeconds);
        minSum += minG;
        maxSum += maxG;
      } else {
        minSum += s.targetGrams;
        maxSum += s.targetGrams;
      }
    }
    return FeedPortions.formatRange(minSum, maxSum);
  }

  int get totalDailyDurationSeconds => _schedules
      .where((s) => s.isEnabled)
      .fold<int>(0, (acc, item) => acc + item.durationSeconds);

  int get activeScheduleCount => _schedules.where((s) => s.isEnabled).length;

  /// Returns the midpoint time-estimated portion grams for a feeding log based on its
  /// dispense duration (1s: 550g-600g, 2s: 1kg-1.1kg, 3s: 1.1kg-1.3kg, 4s: 1.6kg-1.9kg, 5s: 1.6kg-2.3kg)
  /// for numeric calculations while the physical HX711 scale hardware is faulty.
  static double configuredGramsForLog(FeedingLog log) {
    return FeedPortions.displayGramsForLog(log);
  }

  /// Total configured portion grams dispensed today based on recorded feeding logs.
  double get todayDispensedGrams {
    final now = DateTime.now();
    return _history
        .where((l) =>
            l.isSuccess &&
            l.timestamp.year == now.year &&
            l.timestamp.month == now.month &&
            l.timestamp.day == now.day)
        .fold<double>(0.0, (acc, item) => acc + configuredGramsForLog(item));
  }

  /// Formatted estimated weight range dispensed today (e.g., `550g - 600g` or `5.85kg - 7.2kg`).
  String get todayDispensedRangeLabel {
    final now = DateTime.now();
    var minSum = 0.0;
    var maxSum = 0.0;
    for (final l in _history.where((l) =>
        l.isSuccess &&
        l.timestamp.year == now.year &&
        l.timestamp.month == now.month &&
        l.timestamp.day == now.day)) {
      final (minG, maxG) = FeedPortions.rangeGramsForLog(l);
      minSum += minG;
      maxSum += maxG;
    }
    return FeedPortions.formatRange(minSum, maxSum);
  }

  /// Cumulative configured portion grams dispensed across all successful logs.
  double get totalDispensedGrams => _history
      .where((l) => l.isSuccess)
      .fold<double>(0.0, (acc, item) => acc + configuredGramsForLog(item));

  /// Formatted cumulative estimated weight range across all successful logs.
  String get totalDispensedRangeLabel {
    var minSum = 0.0;
    var maxSum = 0.0;
    for (final l in _history.where((l) => l.isSuccess)) {
      final (minG, maxG) = FeedPortions.rangeGramsForLog(l);
      minSum += minG;
      maxSum += maxG;
    }
    return FeedPortions.formatRange(minSum, maxSum);
  }

  /// Number of feeding cycles logged today.
  int get todayFeedCount {
    final now = DateTime.now();
    return _history
        .where((l) =>
            l.timestamp.year == now.year &&
            l.timestamp.month == now.month &&
            l.timestamp.day == now.day)
        .length;
  }

  /// Most recent dispensed portion in grams based on the selected interface/schedule portion.
  double get latestDispensedGrams {
    if (_history.isNotEmpty) return configuredGramsForLog(_history.first);
    if (_telemetry.lastFedGrams > 0) return _telemetry.lastFedGrams;
    return 0.0;
  }

  /// Formatted estimated weight range of the most recent feed (e.g., `550g - 600g`).
  String get latestDispensedRangeLabel {
    if (_history.isNotEmpty) return FeedPortions.formatRangeForLog(_history.first);
    if (_telemetry.lastFedGrams > 0) return FeedPortions.formatWeight(_telemetry.lastFedGrams);
    return '0 g';
  }

  /// Attempts to re-establish the connection and verify live controller heartbeat.
  Future<bool> retryConnection() async {
    if (_isOfflineSimulationMode) {
      _telemetry = _telemetry.copyWith(lastHeartbeat: DateTime.now());
      _lastSyncedAt = DateTime.now();
      notifyListeners();
      return true;
    }
    _connection = FeederConnection.connecting;
    notifyListeners();
    final linkOk = await _adapter.refreshTelemetry();
    await Future<void>.delayed(Duration.zero);
    return linkOk && isDeviceOnline;
  }

  /// Pulls the latest telemetry from the hardware adapter.
  Future<bool> refreshTelemetry() async {
    if (_isOfflineSimulationMode) {
      _telemetry = _telemetry.copyWith(lastHeartbeat: DateTime.now());
      _lastSyncedAt = DateTime.now();
      notifyListeners();
      return true;
    }
    final linkOk = await _adapter.refreshTelemetry();
    await Future<void>.delayed(Duration.zero);
    return linkOk && (_adapter.isMock || _telemetry.isOnline);
  }

  /// Triggers emergency stop on the hardware immediately (always allowed even if command in flight).
  void cancelDispensing() {
    if (_isOfflineSimulationMode) {
      final wasDispensing = _isDispensing;
      final dur = _simDispenseDurationSec ?? 5;
      final trig = _simDispenseTriggerType ?? 'Manual';
      _simDispenseTimer?.cancel();
      _simDispenseTimer = null;
      _simDispenseDurationSec = null;
      _simDispenseTriggerType = null;
      _isDispensing = false;
      final now = DateTime.now();
      if (wasDispensing) {
        final portion = FeedPortions.gramsForDuration(dur);
        final abortedLog = FeedingLog(
          id: 'sim_abort_${now.millisecondsSinceEpoch}',
          timestamp: now,
          targetGrams: portion,
          actualGrams: portion,
          durationSeconds: dur,
          triggerType: '$trig (Cancelled)',
          isSuccess: false,
          batteryVolts: _telemetry.batteryVolts,
          feedLevelPercent: _telemetry.feedLevelPercent,
        );
        _history.insert(0, abortedLog);
        unawaited(alertService.evaluateFeedingLog(abortedLog));
      }
      _telemetry = _telemetry.copyWith(
        status: FeederStatus.idle,
        lastHeartbeat: now,
      );
      notifyListeners();
      return;
    }
    _isDispensing = false;
    notifyListeners();
    _adapter.cancelDispense();
  }

  /// Triggers timed manual feeding on the hardware.
  /// Blocks duplicate rapid taps and blocks queuing commands when the controller is offline.
  Future<bool> triggerManualFeed({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (_isOfflineSimulationMode) {
      return _runSimulatedDispense(
        durationSeconds: durationSeconds,
        triggerType: 'Manual',
        triggerLabel: 'Manual Feed (Simulation)',
      );
    }
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
      final clampedSec = durationSeconds.clamp(1, 60);
      final effectiveTarget = targetGrams > 0 ? targetGrams : (clampedSec * 20.0);
      final ok = await _adapter.triggerManualDispense(
        durationSeconds: clampedSec,
        targetGrams: targetGrams,
      );
      if (ok) {
        unawaited(alertService.notifyDispenseTriggered(
          durationSeconds: clampedSec,
          targetGrams: effectiveTarget,
          triggerLabel: 'Manual Feed',
        ));
      }
      return ok;
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Triggers execution of a specific scheduled routine on the hardware.
  Future<bool> triggerSchedule(FeedingSchedule schedule) async {
    if (_isOfflineSimulationMode) {
      return _runSimulatedDispense(
        durationSeconds: schedule.durationSeconds,
        triggerType: 'Schedule (${schedule.label})',
        triggerLabel: 'Schedule (${schedule.label})',
      );
    }
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
      final ok = await _adapter.triggerScheduleDispense(schedule);
      if (ok) {
        unawaited(alertService.notifyDispenseTriggered(
          durationSeconds: schedule.durationSeconds.clamp(1, 60),
          targetGrams: schedule.targetGrams,
          triggerLabel: 'Schedule (${schedule.label})',
        ));
      }
      return ok;
    } finally {
      _isCommandInFlight = false;
    }
  }

  void addSchedule(FeedingSchedule schedule) {
    if (_isOfflineSimulationMode) {
      _schedules.add(schedule);
      notifyListeners();
      return;
    }
    _scheduleMutationEpoch++;
    _schedules.add(schedule);
    _saveLocalSchedules();
    unawaited(_syncSchedulesViaAdapter(_schedules));
    notifyListeners();
  }

  void insertScheduleAt(int index, FeedingSchedule schedule) {
    if (_isOfflineSimulationMode) {
      if (index >= 0 && index <= _schedules.length) {
        _schedules.insert(index, schedule);
      } else {
        _schedules.add(schedule);
      }
      notifyListeners();
      return;
    }
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
      if (_isOfflineSimulationMode) {
        _schedules[idx] = updated;
        notifyListeners();
        return;
      }
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
      if (_isOfflineSimulationMode) {
        _schedules[idx] = _schedules[idx].copyWith(isEnabled: enabled);
        notifyListeners();
        return;
      }
      _scheduleMutationEpoch++;
      _schedules[idx] = _schedules[idx].copyWith(isEnabled: enabled);
      _saveLocalSchedules();
      unawaited(_syncSchedulesViaAdapter(_schedules));
      notifyListeners();
    }
  }

  void deleteSchedule(String id) {
    if (_isOfflineSimulationMode) {
      _schedules.removeWhere((s) => s.id == id);
      notifyListeners();
      return;
    }
    _scheduleMutationEpoch++;
    _schedules.removeWhere((s) => s.id == id);
    _saveLocalSchedules();
    unawaited(_syncSchedulesViaAdapter(_schedules));
    notifyListeners();
  }

  Future<bool> _syncSchedulesViaAdapter(List<FeedingSchedule> list) async {
    if (_isOfflineSimulationMode) return true;
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
  /// or the local ESP32 REST server when operating in Direct Wi-Fi mode.
  Future<void> syncWithFirebaseCloud() async {
    if (_isOfflineSimulationMode) return;
    if ((_adapter is! FirebaseHardwareAdapter && _adapter is! RestHardwareAdapter) || _disposed) {
      return;
    }
    await refreshSchedulesFromCloud();
    await refreshLogsFromCloud();
  }

  /// Pulls the latest schedules from Firebase RTDB (`/schedules.json`) or ESP32 NVS (`/api/schedules`).
  Future<bool> refreshSchedulesFromCloud() async {
    if (_isOfflineSimulationMode) return true;
    if (_adapter is RestHardwareAdapter) {
      final rest = _adapter as RestHardwareAdapter;
      final remoteList = await rest.fetchSchedulesSnapshot();
      if (remoteList == null) {
        await loadLocalData();
        return false;
      }
      _lastErrorMessage = null;
      if (remoteList.isEmpty && _schedules.isNotEmpty) {
        return rest.syncSchedules(_schedules);
      }
      _schedules = remoteList;
      await _saveLocalSchedules();
      notifyListeners();
      return true;
    }

    if (_adapter is! FirebaseHardwareAdapter) {
      // Mock mode: reload from local persistence
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

  /// Pulls the latest feeding logs from Firebase RTDB (`/logs.json`) or ESP32 ring buffer (`/api/logs`).
  Future<bool> refreshLogsFromCloud() async {
    if (_isOfflineSimulationMode) return true;
    if (_adapter is RestHardwareAdapter) {
      final rest = _adapter as RestHardwareAdapter;
      final remoteLogs = await rest.fetchLogsSnapshot();
      if (remoteLogs == null) {
        await loadLocalData();
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
    }
    _history = remoteLogs;
    await _saveLocalLogs();
    notifyListeners();
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

  String _displayCsvRow(FeedingLog log) {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(log.timestamp);
    final portionStr = FeedPortions.displayGramsForLog(log).toStringAsFixed(1);
    return '${log.id},"$dateStr",${log.triggerType},$portionStr,$portionStr,0.00,0.00%,${log.durationSeconds},${log.feedLevelPercent},${log.batteryVolts},${log.isSuccess ? "PASS" : "FAIL"}';
  }

  String exportCsv() {
    final buffer = StringBuffer();
    buffer.writeln(FeedingLog.csvHeader);
    for (final log in _history) {
      buffer.writeln(_displayCsvRow(log));
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
      final portionStr = FeedPortions.displayGramsForLog(log).toStringAsFixed(1);
      buffer.writeln('   <Row>');
      buffer.writeln('    <Cell><Data ss:Type="String">${log.id}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="String">$dateStr</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="String">${log.triggerType}</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">$portionStr</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">$portionStr</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="Number">0.00</Data></Cell>');
      buffer.writeln('    <Cell><Data ss:Type="String">0.00%</Data></Cell>');
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
    _simDispenseTimer?.cancel();
    _telemetrySub?.cancel();
    _connectionSub?.cancel();
    _logSub?.cancel();
    alertService.dispose();
    _adapter.dispose();
    super.dispose();
  }
}
