import 'dart:async';
import 'dart:math';
import '../../models/telemetry.dart';
import '../../models/schedule.dart';
import '../../models/feeding_log.dart';
import '../../models/feeder_command.dart';
import '../feeder_service.dart';
import 'hardware_adapter.dart';

/// High-fidelity Mock Hardware Simulator.
///
/// Faithfully simulates the physical prototype described in the research methodology:
/// - ESP32 main controller + DS3231 RTC clock
/// - MG996R servo dispenser gate with closed-loop load-cell scale weighing (HX711)
/// - HC-SR04 ultrasonic feed-level depth sensor
/// - 12V solar panel + charge controller + battery voltage ADC divider
///
/// Allows complete end-to-end testing of the mobile app months before the physical
/// machine fabrication is completed.
class MockHardwareAdapter implements FeederHardwareAdapter {
  final _telemetryController = StreamController<FeederTelemetry>.broadcast();
  final _connectionController = StreamController<FeederConnection>.broadcast();
  final _logController = StreamController<FeedingLog>.broadcast();

  final Duration connectDelay;
  final Duration dispenseTickInterval;

  FeederTelemetry _currentTelemetry = FeederTelemetry.initial();
  FeederConnection _currentConnection = FeederConnection.connecting;
  bool _isDispensing = false;
  bool _cancelRequested = false;
  bool _disposed = false;

  // Simulation fault flags for integration testing
  bool simulateMotorJam = false;
  bool _simulateOffline = true;
  bool get simulateOffline => _simulateOffline;
  set simulateOffline(bool value) {
    _simulateOffline = value;
    _currentConnection = value ? FeederConnection.offline : FeederConnection.online;
    if (!_disposed) {
      _connectionController.add(_currentConnection);
    }
  }
  bool simulateSensorError = false;

  final Random _rng = Random();

  final String? _customSourceLabel;
  final HardwareTransportType? _customTransportType;

  MockHardwareAdapter({
    this.connectDelay = const Duration(milliseconds: 600),
    this.dispenseTickInterval = const Duration(milliseconds: 400),
    bool simulateOffline = true,
    String? sourceLabel,
    HardwareTransportType? transportType,
  })  : _simulateOffline = simulateOffline,
        _customSourceLabel = sourceLabel,
        _customTransportType = transportType {
    if (!simulateOffline) {
      _currentConnection = FeederConnection.online;
    }
  }

  @override
  Stream<FeederTelemetry> get telemetryStream => _telemetryController.stream;

  @override
  Stream<FeederConnection> get connectionStream => _connectionController.stream;

  @override
  Stream<FeedingLog> get feedingLogStream => _logController.stream;

  @override
  String get hardwareSourceLabel =>
      _customSourceLabel ?? 'Mock Hardware Simulator (Off-Grid Emulation)';

  @override
  HardwareTransportType get transportType =>
      _customTransportType ?? HardwareTransportType.mockSimulator;

  @override
  bool get isMock => true;

  @override
  Future<void> initialize() async {
    if (connectDelay > Duration.zero) {
      _currentConnection = FeederConnection.connecting;
      _connectionController.add(_currentConnection);
      await Future.delayed(connectDelay);
      if (_disposed) return;
    }

    if (simulateOffline) {
      _currentConnection = FeederConnection.offline;
      _currentTelemetry = FeederTelemetry.initial();
      _telemetryController.add(_currentTelemetry);
    } else {
      _currentConnection = FeederConnection.online;
      _currentTelemetry = FeederTelemetry(
        feedLevelPercent: 78.0,
        batteryVolts: 12.6,
        batteryPercent: 88,
        currentWeightGrams: 0.0,
        status: FeederStatus.idle,
        lastHeartbeat: DateTime.now(),
        lastFedTimestamp: DateTime.now().subtract(const Duration(hours: 3)),
        lastFedGrams: 150.0,
        isSolarCharging: true,
      );
      _telemetryController.add(_currentTelemetry);
    }
    _connectionController.add(_currentConnection);
  }

  @override
  Future<bool> refreshTelemetry() async {
    await Future.delayed(const Duration(milliseconds: 250));
    if (_disposed) return false;

    if (simulateOffline) {
      _currentConnection = FeederConnection.offline;
      _connectionController.add(_currentConnection);
      return false;
    }

    _currentConnection = FeederConnection.online;
    _connectionController.add(_currentConnection);

    // Natural solar/battery fluctuation
    final voltVariation = (_rng.nextDouble() * 0.2) - 0.1;
    final volts = (_currentTelemetry.batteryVolts + voltVariation).clamp(11.2, 13.2);
    final batPct = ((volts - 11.2) / (13.0 - 11.2) * 100).round().clamp(10, 100);

    _currentTelemetry = FeederTelemetry(
      feedLevelPercent: simulateSensorError ? 0.0 : _currentTelemetry.feedLevelPercent,
      batteryVolts: double.parse(volts.toStringAsFixed(2)),
      batteryPercent: batPct,
      currentWeightGrams: _currentTelemetry.currentWeightGrams,
      status: simulateSensorError ? FeederStatus.error : _currentTelemetry.status,
      lastHeartbeat: DateTime.now(),
      lastFedTimestamp: _currentTelemetry.lastFedTimestamp,
      lastFedGrams: _currentTelemetry.lastFedGrams,
      isSolarCharging: _currentTelemetry.isSolarCharging,
    );

    _telemetryController.add(_currentTelemetry);
    return true;
  }

  @override
  Future<bool> triggerManualDispense({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (_isDispensing || _currentConnection != FeederConnection.online) {
      return false;
    }

    final double effectiveTargetGrams = targetGrams > 0 ? targetGrams : (durationSeconds * 20.0);
    _isDispensing = true;
    _cancelRequested = false;

    // Gate opens: status changes to dispensing
    _currentTelemetry = FeederTelemetry(
      feedLevelPercent: _currentTelemetry.feedLevelPercent,
      batteryVolts: _currentTelemetry.batteryVolts,
      batteryPercent: _currentTelemetry.batteryPercent,
      currentWeightGrams: 0.0,
      status: FeederStatus.dispensing,
      lastHeartbeat: DateTime.now(),
      lastFedTimestamp: _currentTelemetry.lastFedTimestamp,
      lastFedGrams: _currentTelemetry.lastFedGrams,
      isSolarCharging: _currentTelemetry.isSolarCharging,
    );
    _telemetryController.add(_currentTelemetry);

    // Incremental ramp across durationSeconds
    final steps = durationSeconds.clamp(1, 30);
    double currentWeight = 0.0;

    for (int i = 1; i <= steps; i++) {
      if (_cancelRequested) break;
      await Future.delayed(dispenseTickInterval);
      if (_cancelRequested) break;

      if (simulateMotorJam && i == 3) {
        // Simulate mechanical auger jam / motor stall
        _currentTelemetry = FeederTelemetry(
          feedLevelPercent: _currentTelemetry.feedLevelPercent,
          batteryVolts: _currentTelemetry.batteryVolts,
          batteryPercent: _currentTelemetry.batteryPercent,
          currentWeightGrams: currentWeight,
          status: FeederStatus.error,
          lastHeartbeat: DateTime.now(),
          lastFedTimestamp: _currentTelemetry.lastFedTimestamp,
          lastFedGrams: _currentTelemetry.lastFedGrams,
          isSolarCharging: _currentTelemetry.isSolarCharging,
        );
        _telemetryController.add(_currentTelemetry);
        _isDispensing = false;
        return false;
      }

      currentWeight = (effectiveTargetGrams / steps) * i;
      _currentTelemetry = FeederTelemetry(
        feedLevelPercent: _currentTelemetry.feedLevelPercent,
        batteryVolts: _currentTelemetry.batteryVolts,
        batteryPercent: _currentTelemetry.batteryPercent,
        currentWeightGrams: currentWeight,
        status: FeederStatus.dispensing,
        lastHeartbeat: DateTime.now(),
        lastFedTimestamp: _currentTelemetry.lastFedTimestamp,
        lastFedGrams: _currentTelemetry.lastFedGrams,
        isSolarCharging: _currentTelemetry.isSolarCharging,
      );
      _telemetryController.add(_currentTelemetry);
    }

    final wasCancelled = _cancelRequested;
    final variance = (_rng.nextDouble() * 3.0) - 1.5; // ±1.5g empirical accuracy per methodology
    final actualGrams = wasCancelled
        ? currentWeight
        : (effectiveTargetGrams + variance).clamp(0.0, 1000.0);

    final newFeedLevel = (_currentTelemetry.feedLevelPercent - (actualGrams / 20.0)).clamp(0.0, 100.0);

    final log = FeedingLog(
      id: 'log_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      targetGrams: effectiveTargetGrams,
      actualGrams: double.parse(actualGrams.toStringAsFixed(1)),
      durationSeconds: wasCancelled ? 1 : durationSeconds,
      triggerType: wasCancelled ? 'Manual (Aborted)' : 'Manual',
      isSuccess: !wasCancelled,
      batteryVolts: _currentTelemetry.batteryVolts,
      feedLevelPercent: newFeedLevel,
    );

    _logController.add(log);

    _isDispensing = false;
    _cancelRequested = false;

    _currentTelemetry = FeederTelemetry(
      feedLevelPercent: newFeedLevel,
      batteryVolts: _currentTelemetry.batteryVolts,
      batteryPercent: _currentTelemetry.batteryPercent,
      currentWeightGrams: 0.0,
      status: newFeedLevel < 20 ? FeederStatus.lowFeed : FeederStatus.idle,
      lastHeartbeat: DateTime.now(),
      lastFedTimestamp: DateTime.now(),
      lastFedGrams: actualGrams,
      isSolarCharging: _currentTelemetry.isSolarCharging,
    );
    _telemetryController.add(_currentTelemetry);

    return !wasCancelled;
  }

  @override
  Future<bool> triggerScheduleDispense(FeedingSchedule schedule) async {
    return triggerManualDispense(
      durationSeconds: schedule.durationSeconds,
      targetGrams: schedule.targetGrams,
    );
  }

  @override
  Future<void> cancelDispense() async {
    if (_isDispensing) {
      _cancelRequested = true;
    }
  }

  @override
  Future<bool> syncSchedules(List<FeedingSchedule> schedules) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _currentConnection == FeederConnection.online;
  }

  @override
  Future<FeederCommand> sendCommand(FeederCommand command) async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (_currentConnection != FeederConnection.online) {
      return command.copyWith(
        status: CommandStatus.failed,
        errorMessage: 'Hardware is offline',
      );
    }

    switch (command.action) {
      case FeederAction.dispense:
        final ok = await triggerManualDispense(
          durationSeconds: command.durationSeconds,
          targetGrams: command.targetGrams,
        );
        return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
      case FeederAction.emergencyStop:
        await cancelDispense();
        return command.copyWith(status: CommandStatus.completed);
      case FeederAction.tareScale:
        tareScale();
        return command.copyWith(status: CommandStatus.completed);
      case FeederAction.calibrateScale:
      case FeederAction.syncClock:
      case FeederAction.restartController:
        return command.copyWith(status: CommandStatus.completed);
    }
  }

  /// Restores simulated ultrasonic hopper capacity to 100%.
  void refillHopper() {
    _currentTelemetry = _currentTelemetry.copyWith(
      feedLevelPercent: 100.0,
      status: FeederStatus.idle,
    );
    _telemetryController.add(_currentTelemetry);
  }

  /// Resets simulated load cell weight to zero.
  void tareScale() {
    _currentTelemetry = _currentTelemetry.copyWith(
      currentWeightGrams: 0.0,
    );
    _telemetryController.add(_currentTelemetry);
  }

  @override
  void dispose() {
    _disposed = true;
    _telemetryController.close();
    _connectionController.close();
    _logController.close();
  }
}
