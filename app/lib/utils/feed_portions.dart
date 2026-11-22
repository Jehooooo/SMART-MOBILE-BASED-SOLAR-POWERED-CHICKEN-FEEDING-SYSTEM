import '../models/feeding_log.dart';

/// FRONTEND DISPLAY-ONLY calibration of the timed gate output, taken from the client's
/// bench measurements while the HX711 load cell is faulty. Never send these values to the
/// ESP32 or Firebase; command and schedule payloads keep their original values.
class FeedPortions {
  FeedPortions._();

  /// Client-measured points: seconds -> grams.
  static const List<List<double>> _points = [
    [1, 600],
    [5, 1000],
    [10, 4000],
    [15, 8000],
  ];
  static const double _gramsPerSecondAbove15 = 800.0; // slope of the 10s->15s segment

  static double gramsForDuration(int seconds) {
    if (seconds <= 0) return 0.0;
    if (seconds <= 1) return 600.0;
    for (var i = 1; i < _points.length; i++) {
      final x0 = _points[i - 1][0];
      final y0 = _points[i - 1][1];
      final x1 = _points[i][0];
      final y1 = _points[i][1];
      if (seconds <= x1) {
        return y0 + (seconds - x0) * (y1 - y0) / (x1 - x0);
      }
    }
    return 8000.0 + (seconds - 15) * _gramsPerSecondAbove15;
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
