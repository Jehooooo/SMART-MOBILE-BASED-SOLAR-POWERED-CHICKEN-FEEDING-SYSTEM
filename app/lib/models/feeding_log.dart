import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

@immutable
class FeedingLog {
  final String id;
  final DateTime timestamp;
  final double targetGrams;
  final double actualGrams;
  final int durationSeconds;
  final String triggerType; // 'Schedule' or 'Manual'
  final bool isSuccess;
  final double batteryVolts;
  final double feedLevelPercent;

  const FeedingLog({
    required this.id,
    required this.timestamp,
    required this.targetGrams,
    required this.actualGrams,
    required this.durationSeconds,
    required this.triggerType,
    this.isSuccess = true,
    this.batteryVolts = 12.4,
    this.feedLevelPercent = 75.0,
  });

  double get errorGrams => actualGrams - targetGrams;

  double get errorPercentage {
    if (targetGrams == 0) return 0.0;
    return ((actualGrams - targetGrams).abs() / targetGrams) * 100.0;
  }

  double get accuracyPercent {
    if (targetGrams == 0) return 100.0;
    return (100.0 - errorPercentage).clamp(0.0, 100.0);
  }

  String get formattedTime => DateFormat('MMM dd, yyyy - hh:mm a').format(timestamp);

  factory FeedingLog.fromMap(String id, Map<dynamic, dynamic> map) {
    final tsMillis = (map['timestamp'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch;
    return FeedingLog(
      id: id,
      timestamp: DateTime.fromMillisecondsSinceEpoch(tsMillis),
      targetGrams: (map['targetGrams'] as num?)?.toDouble() ?? 0.0,
      actualGrams: (map['actualGrams'] as num?)?.toDouble() ?? 0.0,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      triggerType: map['triggerType'] as String? ?? 'Schedule',
      isSuccess: map['isSuccess'] as bool? ?? true,
      batteryVolts: (map['batteryVolts'] as num?)?.toDouble() ?? 12.0,
      feedLevelPercent: (map['feedLevelPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.millisecondsSinceEpoch,
      'targetGrams': targetGrams,
      'actualGrams': actualGrams,
      'durationSeconds': durationSeconds,
      'triggerType': triggerType,
      'isSuccess': isSuccess,
      'batteryVolts': batteryVolts,
      'feedLevelPercent': feedLevelPercent,
    };
  }

  String toCsvRow() {
    final dateStr = DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp);
    return '$id,"$dateStr",$triggerType,$targetGrams,$actualGrams,${errorGrams.toStringAsFixed(2)},${errorPercentage.toStringAsFixed(2)}%,$durationSeconds,$feedLevelPercent,$batteryVolts,${isSuccess ? "PASS" : "FAIL"}';
  }

  static String get csvHeader =>
      'LogID,Timestamp,TriggerType,TargetWeight_g,ActualWeight_g,Error_g,ErrorPercentage,Duration_sec,HopperLevel_pct,Battery_V,Status';
}
