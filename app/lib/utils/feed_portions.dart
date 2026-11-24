import '../models/feeding_log.dart';

/// FRONTEND DISPLAY-ONLY time-based weight estimation ranges derived from bench trials
/// while the onboard HX711 load cell hardware is bypassed/faulty:
/// - 1s -> 550g - 600g   (midpoint 575 g)
/// - 2s -> 1kg - 1.1kg   (midpoint 1050 g)
/// - 3s -> 1.1kg - 1.3kg (midpoint 1200 g)
/// - 4s -> 1.6kg - 1.9kg (midpoint 1750 g)
/// - 5s -> 1.6kg - 2.3kg (midpoint 1950 g)
/// - >5s -> linear range extrapolation (+320 g/s min, +460 g/s max)
/// Never send these values to the ESP32 or Firebase; command and schedule payloads keep their original values.
class FeedPortions {
  FeedPortions._();

  /// Returns `(minGrams, maxGrams)` estimated for a given gate open [seconds].
  static (double, double) rangeGramsForDuration(int seconds) {
    if (seconds <= 0) return (0.0, 0.0);
    switch (seconds) {
      case 1:
        return (550.0, 600.0);
      case 2:
        return (1000.0, 1100.0);
      case 3:
        return (1100.0, 1300.0);
      case 4:
        return (1600.0, 1900.0);
      case 5:
        return (1600.0, 2300.0);
      default:
        final extra = seconds - 5;
        return (1600.0 + extra * 320.0, 2300.0 + extra * 460.0);
    }
  }

  /// Midpoint estimated grams for numeric progress bars, totals, and numeric spreadsheet cells.
  static double gramsForDuration(int seconds) {
    if (seconds <= 0) return 0.0;
    final (minG, maxG) = rangeGramsForDuration(seconds);
    return ((minG + maxG) / 2.0 * 10).round() / 10;
  }

  /// Standard spaced formatting: `g` below 1000 g (`600 g`), trimmed `kg` at >= 1000 g (`1.1 kg`).
  static String formatWeight(double grams) {
    final sign = grams < 0 ? '-' : '';
    final rounded = (grams.abs() * 10).round() / 10;
    if (rounded < 1000) {
      return rounded == rounded.roundToDouble()
          ? '$sign${rounded.toInt()} g'
          : '$sign${rounded.toStringAsFixed(1)} g';
    }
    var kg = (rounded / 1000).toStringAsFixed(2);
    kg = kg.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$sign$kg kg';
  }

  /// Compact unit formatting without space (`550g`, `1kg`, `1.1kg`) used inside range labels.
  static String formatCompactWeight(double grams) {
    final sign = grams < 0 ? '-' : '';
    final rounded = (grams.abs() * 10).round() / 10;
    if (rounded < 1000) {
      return rounded == rounded.roundToDouble()
          ? '$sign${rounded.toInt()}g'
          : '$sign${rounded.toStringAsFixed(1)}g';
    }
    var kg = (rounded / 1000).toStringAsFixed(2);
    kg = kg.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return '$sign${kg}kg';
  }

  /// Formats an arbitrary `(minGrams, maxGrams)` pair as e.g. `550g - 600g` or `1kg - 1.1kg`.
  static String formatRange(double minGrams, double maxGrams) {
    if (minGrams <= 0 && maxGrams <= 0) return '0 g';
    if ((maxGrams - minGrams).abs() < 0.05) return formatWeight(maxGrams);
    return '${formatCompactWeight(minGrams)} - ${formatCompactWeight(maxGrams)}';
  }

  /// Formats the estimated weight range for [seconds], e.g.:
  /// 1 -> `550g - 600g`, 2 -> `1kg - 1.1kg`, 3 -> `1.1kg - 1.3kg`,
  /// 4 -> `1.6kg - 1.9kg`, 5 -> `1.6kg - 2.3kg`.
  static String formatRangeForDuration(int seconds) {
    if (seconds <= 0) return '0 g';
    final (minG, maxG) = rangeGramsForDuration(seconds);
    return formatRange(minG, maxG);
  }

  static String formatForDuration(int seconds) => formatRangeForDuration(seconds);

  /// Returns `(minGrams, maxGrams)` for a feeding log entry.
  static (double, double) rangeGramsForLog(FeedingLog log) {
    if (log.durationSeconds > 0) return rangeGramsForDuration(log.durationSeconds);
    final fallback = log.targetGrams > 0 ? log.targetGrams : log.actualGrams;
    return (fallback, fallback);
  }

  /// Formats the estimated range for a feeding log entry (e.g., `550g - 600g`).
  static String formatRangeForLog(FeedingLog log) {
    if (log.durationSeconds > 0) return formatRangeForDuration(log.durationSeconds);
    return formatWeight(displayGramsForLog(log));
  }

  /// Midpoint display grams for a log (used for numeric cells and progress ratios).
  static double displayGramsForLog(FeedingLog log) {
    if (log.durationSeconds > 0) return gramsForDuration(log.durationSeconds);
    if (log.targetGrams > 0) return log.targetGrams;
    return log.actualGrams;
  }
}
