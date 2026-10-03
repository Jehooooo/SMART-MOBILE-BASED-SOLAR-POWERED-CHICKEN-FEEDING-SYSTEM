import 'package:flutter/foundation.dart';

@immutable
class FeedingSchedule {
  final String id;
  final String label;
  final int hour;
  final int minute;
  final double targetGrams;
  final bool isEnabled;
  final List<int> daysOfWeek; // 1 = Monday, 7 = Sunday

  const FeedingSchedule({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.targetGrams,
    this.isEnabled = true,
    this.daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
  });

  String get timeFormatted {
    final period = hour >= 12 ? 'PM' : 'AM';
    final h = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final m = minute.toString().padLeft(2, '0');
    return '$h:$m $period';
  }

  FeedingSchedule copyWith({
    String? label,
    int? hour,
    int? minute,
    double? targetGrams,
    bool? isEnabled,
    List<int>? daysOfWeek,
  }) {
    return FeedingSchedule(
      id: id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      targetGrams: targetGrams ?? this.targetGrams,
      isEnabled: isEnabled ?? this.isEnabled,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    );
  }

  factory FeedingSchedule.fromMap(String id, Map<dynamic, dynamic> map) {
    return FeedingSchedule(
      id: id,
      label: map['label'] as String? ?? 'Scheduled Feed',
      hour: (map['hour'] as num?)?.toInt() ?? 6,
      minute: (map['minute'] as num?)?.toInt() ?? 0,
      targetGrams: (map['targetGrams'] as num?)?.toDouble() ?? 150.0,
      isEnabled: map['isEnabled'] as bool? ?? true,
      daysOfWeek: (map['daysOfWeek'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [1, 2, 3, 4, 5, 6, 7],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'hour': hour,
      'minute': minute,
      'targetGrams': targetGrams,
      'isEnabled': isEnabled,
      'daysOfWeek': daysOfWeek,
    };
  }
}
