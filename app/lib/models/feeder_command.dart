import 'package:flutter/foundation.dart';

/// Actions that the mobile application can command the physical feeder to execute.
enum FeederAction {
  dispense,
  emergencyStop,
  calibrateScale,
  syncClock,
  tareScale,
  setServoAngle,
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
      case FeederAction.setServoAngle:
        return 'SERVO_TEST';
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
      case 'SERVO_TEST':
      case 'TEST_SERVO':
        return FeederAction.setServoAngle;
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
  final int durationSeconds;
  final double targetGrams;
  final double? actualGrams;
  final int? servoAngle;
  final String? triggerType;
  final String? scheduleSlotKey;
  final DateTime timestamp;
  final CommandStatus status;
  final String? errorMessage;

  const FeederCommand({
    required this.id,
    required this.action,
    this.durationSeconds = 5,
    this.targetGrams = 0.0,
    this.actualGrams,
    this.servoAngle,
    this.triggerType,
    this.scheduleSlotKey,
    required this.timestamp,
    this.status = CommandStatus.pending,
    this.errorMessage,
  });

  FeederCommand copyWith({
    CommandStatus? status,
    String? errorMessage,
    int? durationSeconds,
    double? targetGrams,
    double? actualGrams,
    int? servoAngle,
    String? triggerType,
    String? scheduleSlotKey,
  }) {
    return FeederCommand(
      id: id,
      action: action,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      targetGrams: targetGrams ?? this.targetGrams,
      actualGrams: actualGrams ?? this.actualGrams,
      servoAngle: servoAngle ?? this.servoAngle,
      triggerType: triggerType ?? this.triggerType,
      scheduleSlotKey: scheduleSlotKey ?? this.scheduleSlotKey,
      timestamp: timestamp,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action.commandString,
      'durationSeconds': durationSeconds,
      'targetGrams': targetGrams,
      if (actualGrams != null) 'actualGrams': actualGrams,
      if (servoAngle != null) 'servoAngle': servoAngle,
      if (triggerType != null) 'triggerType': triggerType,
      if (scheduleSlotKey != null) 'scheduleSlotKey': scheduleSlotKey,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'status': status.name,
      if (errorMessage != null) 'errorMessage': errorMessage,
    };
  }

  factory FeederCommand.fromJson(Map<String, dynamic> json) {
    return FeederCommand(
      id: json['id'] as String? ?? 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.fromString(json['action'] as String? ?? 'DISPENSE'),
      durationSeconds: (json['durationSeconds'] as num?)?.toInt() ??
          (json['duration'] as num?)?.toInt() ??
          5,
      targetGrams: (json['targetGrams'] as num?)?.toDouble() ?? 0.0,
      actualGrams: (json['actualGrams'] as num?)?.toDouble(),
      servoAngle: (json['servoAngle'] as num?)?.toInt() ?? (json['angle'] as num?)?.toInt(),
      triggerType: json['triggerType'] as String?,
      scheduleSlotKey: json['scheduleSlotKey'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch((json['timestamp'] as num).toInt())
          : DateTime.now(),
      status: CommandStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => CommandStatus.pending,
      ),
      errorMessage: json['errorMessage'] as String?,
    );
  }

  factory FeederCommand.dispense({
    int durationSeconds = 5,
    double targetGrams = 0.0,
    String triggerType = 'Manual',
    String? scheduleSlotKey,
  }) {
    return FeederCommand(
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.dispense,
      durationSeconds: durationSeconds,
      targetGrams: targetGrams,
      triggerType: triggerType,
      scheduleSlotKey: scheduleSlotKey,
      timestamp: DateTime.now(),
    );
  }

  factory FeederCommand.servoTest(int angleDegrees) {
    final clamped = angleDegrees.clamp(0, 90);
    return FeederCommand(
      id: 'cmd_servo_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.setServoAngle,
      durationSeconds: 0,
      targetGrams: 0.0,
      servoAngle: clamped,
      timestamp: DateTime.now(),
    );
  }

  factory FeederCommand.emergencyStop() {
    return FeederCommand(
      id: 'cmd_stop_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.emergencyStop,
      durationSeconds: 0,
      timestamp: DateTime.now(),
    );
  }

  factory FeederCommand.tareScale() {
    return FeederCommand(
      id: 'cmd_tare_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.tareScale,
      durationSeconds: 0,
      timestamp: DateTime.now(),
    );
  }
}
