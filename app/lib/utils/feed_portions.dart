import '../models/feeding_log.dart';

/// FRONTEND DISPLAY-ONLY calibration of the timed gate output, computed from empirical
/// physical bench trials while the onboard HX711 load cell is faulty:
/// - 1s (5 trials: 585g, 600g, 589g, 620g, 593g) -> mean = 597.4 g
/// - 2s (2 trials: 1.069kg, 1.115kg)             -> mean = 1092.0 g (1.09 kg)
/// - 3s (2 trials: 1.253kg, 1.245kg)             -> mean = 1249.0 g (1.25 kg)
/// - 4s (6 trials: 1.317, 1.699, 1.933, 1.917, 1.867, 1.970 kg) -> mean = 1783.8 g (1.78 kg)
/// - 5s (6 trials: 1.625, 1.805, 1.896, 2.098, 2.169, 2.202 kg) -> mean = 1965.8 g (1.97 kg)
/// Never send these values to the ESP32 or Firebase; command and schedule payloads keep their original values.
class FeedPortions {
  FeedPortions._();

  /// Empirical bench-tested mean points: seconds -> grams.
  static const List<List<double>> _points = [
    [1, 597.4],
    [2, 1092.0],
    [3, 1249.0],
    [4, 1783.8],
    [5, 1965.8],
  ];
  static const double _gramsPerSecondAbove5 = 342.9; // OLS regression slope across 1s..5s trials

  static double gramsForDuration(int seconds) {
    if (seconds <= 0) return 0.0;
    if (seconds <= 1) return 597.4;
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
    final raw = 1965.8 + (seconds - 5) * _gramsPerSecondAbove5;
    return (raw * 10).round() / 10;
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
