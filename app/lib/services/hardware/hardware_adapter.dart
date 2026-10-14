import 'dart:async';
import '../../models/telemetry.dart';
import '../../models/schedule.dart';
import '../../models/feeding_log.dart';
import '../../models/feeder_command.dart';
import '../feeder_service.dart';

/// Communication protocol / transport used to connect to the physical feeder.
enum HardwareTransportType {
  mockSimulator,
  firebaseCloud,
  localRestHttp,
  bluetoothLowEnergy;

  String get displayName {
    switch (this) {
      case HardwareTransportType.mockSimulator:
        return 'Mock Simulator (Development)';
      case HardwareTransportType.firebaseCloud:
        return 'ESP32 Cloud (Firebase RTDB)';
      case HardwareTransportType.localRestHttp:
        return 'ESP32 Local Wi-Fi (REST HTTP)';
      case HardwareTransportType.bluetoothLowEnergy:
        return 'Bluetooth Low Energy (BLE)';
    }
  }
}

/// Abstract Hardware Integration Layer.
///
/// Decouples the Flutter UI and state management from the underlying physical
/// machine transport. Whether the machine connects via Firebase Cloud, local Wi-Fi
/// REST API, or Bluetooth Low Energy, the app interacts with this uniform interface.
abstract class FeederHardwareAdapter {
  /// Stream emitting live telemetry updates received from the hardware.
  Stream<FeederTelemetry> get telemetryStream;

  /// Stream emitting network/hardware connectivity status transitions.
  Stream<FeederConnection> get connectionStream;

  /// Stream emitting new feeding logs recorded by the hardware's load cell scale.
  Stream<FeedingLog> get feedingLogStream;

  /// Human-readable label of the current hardware source shown in UI status badges.
  String get hardwareSourceLabel;

  /// Type of transport currently in use.
  HardwareTransportType get transportType;

  /// True if running against simulated/mock hardware.
  bool get isMock;

  /// Connects to the hardware or cloud transport.
  Future<void> initialize();

  /// Requests an immediate refresh of telemetry data.
  Future<bool> refreshTelemetry();

  /// Triggers a manual dispense operation for [targetGrams] on the hardware.
  Future<bool> triggerManualDispense(double targetGrams);

  /// Sends an immediate emergency stop signal to close the servo gate and stop auger.
  Future<void> cancelDispense();

  /// Synchronizes active feeding schedules to the hardware's onboard RTC memory.
  Future<bool> syncSchedules(List<FeedingSchedule> schedules);

  /// Sends a generic hardware command and waits for acknowledgment.
  Future<FeederCommand> sendCommand(FeederCommand command);

  /// Disconnects and releases resources.
  void dispose();
}
