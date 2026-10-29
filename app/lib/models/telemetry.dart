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
  final DateTime? lastHeartbeat;
  final DateTime? lastFedTimestamp;
  final double lastFedGrams;
  final bool isSolarCharging;
  final String? sensorError;

  const FeederTelemetry({
    required this.feedLevelPercent,
    required this.batteryVolts,
    required this.batteryPercent,
    required this.currentWeightGrams,
    required this.status,
    this.lastHeartbeat,
    this.lastFedTimestamp,
    this.lastFedGrams = 0.0,
    this.isSolarCharging = true,
    this.sensorError,
  });

  bool get isOnline {
    if (lastHeartbeat == null) return false;
    final diff = DateTime.now().difference(lastHeartbeat!);
    return diff.inMinutes < 3 && diff.inMinutes >= -5;
  }

  factory FeederTelemetry.initial() {
    return FeederTelemetry(
      feedLevelPercent: 78.0,
      batteryVolts: 12.6,
      batteryPercent: 88,
      currentWeightGrams: 0.0,
      status: FeederStatus.idle,
      lastHeartbeat: null,
      lastFedTimestamp: DateTime.now().subtract(const Duration(hours: 3)),
      lastFedGrams: 150.0,
      isSolarCharging: true,
    );
  }

  factory FeederTelemetry.fromMap(Map<dynamic, dynamic> map) {
    FeederStatus parsedStatus = FeederStatus.idle;
    final statusStr = map['status']?.toString().toLowerCase() ?? '';
    final rawSensorErr = map['sensorError']?.toString();
    final hasSensorErr = rawSensorErr != null && rawSensorErr.trim().isNotEmpty;

    if (statusStr.contains('dispens')) {
      parsedStatus = FeederStatus.dispensing;
    } else if (statusStr.contains('err') || hasSensorErr) {
      parsedStatus = FeederStatus.error;
    } else if (statusStr.contains('feed')) {
      parsedStatus = FeederStatus.lowFeed;
    } else if (statusStr.contains('bat')) {
      parsedStatus = FeederStatus.lowBattery;
    }

    final hbMillis = (map['lastHeartbeat'] as num?)?.toInt() ?? 0;
    final lastFedMillis = (map['lastFedTimestamp'] as num?)?.toInt();

    final rawFeed = (map['feedLevelPercent'] as num?)?.toDouble() ?? 0.0;
    final rawVolts = (map['batteryVolts'] as num?)?.toDouble() ?? 12.0;
    final rawBatPct = (map['batteryPercent'] as num?)?.toInt() ?? 50;
    final rawWeight = (map['currentWeightGrams'] as num?)?.toDouble() ?? 0.0;

    return FeederTelemetry(
      feedLevelPercent: rawFeed.isFinite ? rawFeed.clamp(0.0, 100.0) : 0.0,
      batteryVolts: rawVolts.isFinite ? rawVolts.clamp(0.0, 24.0) : 0.0,
      batteryPercent: rawBatPct.clamp(0, 100),
      currentWeightGrams: rawWeight.isFinite ? rawWeight.clamp(-500.0, 10000.0) : 0.0,
      status: parsedStatus,
      lastHeartbeat: hbMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(hbMillis)
          : null,
      lastFedTimestamp: lastFedMillis != null && lastFedMillis > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastFedMillis)
          : null,
      lastFedGrams: (map['lastFedGrams'] as num?)?.toDouble() ?? 0.0,
      isSolarCharging: map['isSolarCharging'] as bool? ?? true,
      sensorError: hasSensorErr ? rawSensorErr : null,
    );
  }

  FeederTelemetry copyWith({
    double? feedLevelPercent,
    double? batteryVolts,
    int? batteryPercent,
    double? currentWeightGrams,
    FeederStatus? status,
    DateTime? lastHeartbeat,
    bool clearHeartbeat = false,
    DateTime? lastFedTimestamp,
    double? lastFedGrams,
    bool? isSolarCharging,
    String? sensorError,
    bool clearSensorError = false,
  }) {
    return FeederTelemetry(
      feedLevelPercent: feedLevelPercent ?? this.feedLevelPercent,
      batteryVolts: batteryVolts ?? this.batteryVolts,
      batteryPercent: batteryPercent ?? this.batteryPercent,
      currentWeightGrams: currentWeightGrams ?? this.currentWeightGrams,
      status: status ?? this.status,
      lastHeartbeat: clearHeartbeat ? null : (lastHeartbeat ?? this.lastHeartbeat),
      lastFedTimestamp: lastFedTimestamp ?? this.lastFedTimestamp,
      lastFedGrams: lastFedGrams ?? this.lastFedGrams,
      isSolarCharging: isSolarCharging ?? this.isSolarCharging,
      sensorError: clearSensorError ? null : (sensorError ?? this.sensorError),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'feedLevelPercent': feedLevelPercent,
      'batteryVolts': batteryVolts,
      'batteryPercent': batteryPercent,
      'currentWeightGrams': currentWeightGrams,
      'status': status.name,
      'lastHeartbeat': lastHeartbeat?.millisecondsSinceEpoch,
      'lastFedTimestamp': lastFedTimestamp?.millisecondsSinceEpoch,
      'lastFedGrams': lastFedGrams,
      'isSolarCharging': isSolarCharging,
      if (sensorError != null) 'sensorError': sensorError,
    };
  }
}
