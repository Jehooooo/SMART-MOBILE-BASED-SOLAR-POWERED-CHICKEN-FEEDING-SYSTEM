import 'package:flutter/foundation.dart';

/// Actions that the mobile application can command the physical feeder to execute.
enum FeederAction {
  dispense,
  emergencyStop,
  calibrateScale,
  syncClock,
  tareScale,
  restartController;

  String get commandString {
    switch (this) {
      case FeederAction.dispense:
        return 'DISPENSE';
      case FeederAction.emergencyStop:
        return 'EMERGENCY_STOP';
      case FeederAction.calibrateScale:
        return 'CALIBRATE_SCALE';
      case FeederAction.syncClock:
        return 'SYNC_CLOCK';
      case FeederAction.tareScale:
        return 'TARE_SCALE';
      case FeederAction.restartController:
        return 'RESTART';
    }
  }

  static FeederAction fromString(String val) {
    switch (val.toUpperCase()) {
      case 'DISPENSE':
        return FeederAction.dispense;
      case 'EMERGENCY_STOP':
      case 'STOP':
        return FeederAction.emergencyStop;
      case 'CALIBRATE_SCALE':
        return FeederAction.calibrateScale;
      case 'SYNC_CLOCK':
        return FeederAction.syncClock;
      case 'TARE_SCALE':
        return FeederAction.tareScale;
      case 'RESTART':
        return FeederAction.restartController;
      default:
        return FeederAction.dispense;
    }
  }
}

/// Status of a command sent to the feeder hardware.
enum CommandStatus {
  pending,
  inProgress,
  completed,
  aborted,
  failed,
  timeout;

  String get displayName {
    switch (this) {
      case CommandStatus.pending:
        return 'Queued';
      case CommandStatus.inProgress:
        return 'Executing...';
      case CommandStatus.completed:
        return 'Completed';
      case CommandStatus.aborted:
        return 'Aborted by User';
      case CommandStatus.failed:
        return 'Failed';
      case CommandStatus.timeout:
        return 'Timed Out';
    }
  }
}

/// Data contract representing a command sent to the ESP32 hardware.
@immutable
class FeederCommand {
  final String id;
  final FeederAction action;
  final double targetGrams;
  final DateTime timestamp;
  final CommandStatus status;
  final String? errorMessage;

  const FeederCommand({
    required this.id,
    required this.action,
    this.targetGrams = 0.0,
    required this.timestamp,
    this.status = CommandStatus.pending,
    this.errorMessage,
  });

  FeederCommand copyWith({
    CommandStatus? status,
    String? errorMessage,
  }) {
    return FeederCommand(
      id: id,
      action: action,
      targetGrams: targetGrams,
      timestamp: timestamp,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action.commandString,
      'targetGrams': targetGrams,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status.name,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  factory FeederCommand.fromJson(Map<String, dynamic> json) {
    return FeederCommand(
      id: json['id'] as String? ?? 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.fromString(json['action'] as String? ?? 'DISPENSE'),
      targetGrams: (json['targetGrams'] as num?)?.toDouble() ?? 0.0,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      status: CommandStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => CommandStatus.pending,
      ),
      errorMessage: json['errorMessage'] as String?,
    );
  }
}
