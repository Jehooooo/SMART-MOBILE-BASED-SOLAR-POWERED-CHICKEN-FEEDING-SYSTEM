import 'package:flutter/foundation.dart';

enum FeederStatus {
  idle,
  dispensing,
  lowFeed,
  lowBattery,
  offline,
  error;

  String get displayName {
    switch (this) {
      case FeederStatus.idle:
        return 'Ready / Standby';
      case FeederStatus.dispensing:
        return 'Dispensing Feed...';
      case FeederStatus.lowFeed:
        return 'Low Feed Warning';
      case FeederStatus.lowBattery:
        return 'Low Battery Warning';
      case FeederStatus.offline:
        return 'Device Offline';
      case FeederStatus.error:
        return 'System Error';
    }
  }
}

@immutable
class FeederTelemetry {
  final double feedLevelPercent;
  final double batteryVolts;
  final int batteryPercent;
  final double currentWeightGrams;
  final FeederStatus status;
  final DateTime lastHeartbeat;
  final DateTime? lastFedTimestamp;
  final double lastFedGrams;
  final bool isSolarCharging;

  const FeederTelemetry({
    required this.feedLevelPercent,
    required this.batteryVolts,
    required this.batteryPercent,
    required this.currentWeightGrams,
    required this.status,
    required this.lastHeartbeat,
    this.lastFedTimestamp,
    this.lastFedGrams = 0.0,
    this.isSolarCharging = true,
  });

  bool get isOnline {
    final diff = DateTime.now().difference(lastHeartbeat);
    return diff.inMinutes < 3;
  }

  factory FeederTelemetry.initial() {
    return FeederTelemetry(
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
  }

  factory FeederTelemetry.fromMap(Map<dynamic, dynamic> map) {
    FeederStatus parsedStatus = FeederStatus.idle;
    final statusStr = map['status']?.toString().toLowerCase() ?? '';
    if (statusStr.contains('dispens')) {
      parsedStatus = FeederStatus.dispensing;
    } else if (statusStr.contains('feed')) {
      parsedStatus = FeederStatus.lowFeed;
    } else if (statusStr.contains('bat')) {
      parsedStatus = FeederStatus.lowBattery;
    } else if (statusStr.contains('err')) {
      parsedStatus = FeederStatus.error;
    }

    final hbMillis = (map['lastHeartbeat'] as num?)?.toInt() ?? 0;
    final lastFedMillis = (map['lastFedTimestamp'] as num?)?.toInt();

    return FeederTelemetry(
      feedLevelPercent: (map['feedLevelPercent'] as num?)?.toDouble() ?? 0.0,
      batteryVolts: (map['batteryVolts'] as num?)?.toDouble() ?? 12.0,
      batteryPercent: (map['batteryPercent'] as num?)?.toInt() ?? 50,
      currentWeightGrams: (map['currentWeightGrams'] as num?)?.toDouble() ?? 0.0,
      status: parsedStatus,
      lastHeartbeat: hbMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(hbMillis)
          : DateTime.now(),
      lastFedTimestamp: lastFedMillis != null && lastFedMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastFedMillis)
          : null,
      lastFedGrams: (map['lastFedGrams'] as num?)?.toDouble() ?? 0.0,
      isSolarCharging: map['isSolarCharging'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'feedLevelPercent': feedLevelPercent,
      'batteryVolts': batteryVolts,
      'batteryPercent': batteryPercent,
      'currentWeightGrams': currentWeightGrams,
      'status': status.name,
      'lastHeartbeat': lastHeartbeat.millisecondsSinceEpoch,
      'lastFedTimestamp': lastFedTimestamp?.millisecondsSinceEpoch,
      'lastFedGrams': lastFedGrams,
      'isSolarCharging': isSolarCharging,
    };
  }
}
