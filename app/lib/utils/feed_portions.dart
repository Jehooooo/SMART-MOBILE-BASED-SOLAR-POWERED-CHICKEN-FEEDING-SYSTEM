import '../models/feeding_log.dart';

/// FRONTEND DISPLAY-ONLY time-based weight estimation derived from physical bench trials
/// while the onboard HX711 load cell hardware is bypassed/faulty:
/// - 1s ≈ 600 g   (bench trials: 585–620 g, avg 597.4 g)
/// - 2s ≈ 1.1 kg  (bench trials: 1.069–1.115 kg, avg 1.092 kg)
/// - 3s ≈ 1.25 kg (bench trials: 1.245–1.253 kg, avg 1.249 kg)
/// - 4s ≈ 1.8 kg  (bench trials: 1.317–1.970 kg, avg 1.784 kg)
/// - 5s ≈ 2 kg    (bench trials: 1.625–2.202 kg, avg 1.966 kg)
/// - >5s: linear flow-rate estimation (+400 g/s, e.g., 10s ≈ 4 kg, 15s ≈ 6 kg)
/// Never send these values to the ESP32 or Firebase; command and schedule payloads keep their original values.
class FeedPortions {
  FeedPortions._();

  /// Rounded bench-estimated lookup points: seconds -> estimated grams.
  static const List<List<double>> _points = [
    [1, 600.0],
    [2, 1100.0],
    [3, 1250.0],
    [4, 1800.0],
    [5, 2000.0],
  ];
  static const double _estimatedGramsPerSecAbove5 = 400.0; // 2000 g / 5 s steady-state rate

  static double gramsForDuration(int seconds) {
    if (seconds <= 0) return 0.0;
    if (seconds <= 1) return 600.0;
    for (var i = 1; i < _points.length; i++) {
      final x0 = _points[i - 1][0];
      final y0 = _points[i - 1][1];
      final x1 = _points[i][0];
      final y1 = _points[i][1];
      if (seconds <= x1) {
        final raw = y0 + (seconds - x0) * (y1 - y0) / (x1 - x0);
        return (raw * 10).round() / 10;
      }
    }
    return 2000.0 + (seconds - 5) * _estimatedGramsPerSecAbove5;
  }

  /// g below 1000 g, kg at 1000 g or more (trailing zeros trimmed: 1 kg, 1.8 kg, 1.25 kg).
  static String formatWeight(double grams) {
    final sign = grams < 0 ? '-' : '';
    final rounded = (grams.abs() * 10).round() / 10; // 1 decimal
    if (rounded < 1000) {
      return rounded == rounded.roundToDouble()
          ? '$sign${rounded.toInt()} g'
          : '$sign${rounded.toStringAsFixed(1)} g';
    }
    var kg = (rounded / 1000).toStringAsFixed(2);
    kg = kg.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$sign$kg kg';
  }

  static String formatForDuration(int seconds) => formatWeight(gramsForDuration(seconds));

  /// Display grams for a log: the calibrated portion for its duration. The stored targetGrams
  /// (legacy 20 g/s) and the raw actualGrams are ignored whenever a duration exists.
  static double displayGramsForLog(FeedingLog log) {
    if (log.durationSeconds > 0) return gramsForDuration(log.durationSeconds);
    if (log.targetGrams > 0) return log.targetGrams;
    return log.actualGrams;
  }
}
