import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/telemetry.dart';
import '../../models/schedule.dart';
import '../../models/feeding_log.dart';
import '../../models/feeder_command.dart';
import '../feeder_service.dart';
import 'hardware_adapter.dart';

/// Direct Local Wi-Fi HTTP Hardware Adapter.
///
/// Designed for off-grid poultry farms without internet connectivity.
/// The ESP32 hosts an embedded web server (SoftAP mode or local farm router).
/// The mobile app communicates via REST endpoints:
/// - `GET /api/telemetry` -> returns FeederTelemetry JSON
/// - `POST /api/dispense` -> triggers servo gate with target weight
/// - `POST /api/stop` -> immediate emergency cutoff
/// - `POST /api/schedules` -> synchronizes schedule table to onboard RTC
class RestHardwareAdapter implements FeederHardwareAdapter {
  final String host;
  final int port;

  final _telemetryController = StreamController<FeederTelemetry>.broadcast();
  final _connectionController = StreamController<FeederConnection>.broadcast();
  final _logController = StreamController<FeedingLog>.broadcast();

  Timer? _pollTimer;
  FeederConnection _currentConnection = FeederConnection.connecting;
  bool _disposed = false;

  RestHardwareAdapter({
    this.host = '192.168.4.1', // Default ESP32 SoftAP IP
    this.port = 80,
  });

  String get _baseUrl => 'http://$host:$port';

  @override
  Stream<FeederTelemetry> get telemetryStream => _telemetryController.stream;

  @override
  Stream<FeederConnection> get connectionStream => _connectionController.stream;

  @override
  Stream<FeedingLog> get feedingLogStream => _logController.stream;

  @override
  String get hardwareSourceLabel => 'ESP32 Local Wi-Fi ($_baseUrl)';

  @override
  HardwareTransportType get transportType => HardwareTransportType.localRestHttp;

  @override
  bool get isMock => false;

  @override
  Future<void> initialize() async {
    _connectionController.add(FeederConnection.connecting);
    await refreshTelemetry();

    // Poll every 3 seconds when connected
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_disposed) refreshTelemetry();
    });
  }

  @override
  Future<bool> refreshTelemetry() async {
    if (kIsWeb) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(Uri.parse('$_baseUrl/api/telemetry'));
      final response = await request.close();

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final map = jsonDecode(body) as Map<dynamic, dynamic>;
        final telemetry = FeederTelemetry.fromMap(map);
        _telemetryController.add(telemetry);
        _setConnection(FeederConnection.online);
        return true;
      } else {
        _setConnection(FeederConnection.offline);
      }
    } catch (_) {
      _setConnection(FeederConnection.offline);
    }
    return false;
  }

  void _setConnection(FeederConnection conn) {
    if (_currentConnection != conn) {
      _currentConnection = conn;
      _connectionController.add(_currentConnection);
    }
  }

  @override
  Future<bool> triggerManualDispense({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (kIsWeb) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.postUrl(Uri.parse('$_baseUrl/api/dispense'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'durationSeconds': durationSeconds,
        'duration': durationSeconds,
        'targetGrams': targetGrams,
      }));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('RestHardwareAdapter dispense error: $e');
      return false;
    }
  }

  @override
  Future<void> cancelDispense() async {
    if (kIsWeb) return;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.postUrl(Uri.parse('$_baseUrl/api/stop'));
      await request.close();
    } catch (e) {
      debugPrint('RestHardwareAdapter stop error: $e');
    }
  }

  @override
  Future<bool> syncSchedules(List<FeedingSchedule> schedules) async {
    if (kIsWeb) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.postUrl(Uri.parse('$_baseUrl/api/schedules'));
      request.headers.contentType = ContentType.json;
      final payload = schedules.map((s) => s.toMap()).toList();
      request.write(jsonEncode(payload));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('RestHardwareAdapter sync error: $e');
      return false;
    }
  }

  Future<bool> tareScale() async {
    if (kIsWeb) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.postUrl(Uri.parse('$_baseUrl/api/tare'));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('RestHardwareAdapter tare error: $e');
      return false;
    }
  }

  Future<bool> calibrateScale(double knownGrams) async {
    if (kIsWeb) return false;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 2);
      final request = await client.postUrl(Uri.parse('$_baseUrl/api/calibrate'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'targetGrams': knownGrams}));
      final response = await request.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('RestHardwareAdapter calibrate error: $e');
      return false;
    }
  }

  @override
  Future<FeederCommand> sendCommand(FeederCommand command) async {
    if (command.action == FeederAction.dispense) {
      final ok = await triggerManualDispense(
        durationSeconds: command.durationSeconds,
        targetGrams: command.targetGrams,
      );
      return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
    } else if (command.action == FeederAction.emergencyStop) {
      await cancelDispense();
      return command.copyWith(status: CommandStatus.completed);
    } else if (command.action == FeederAction.tareScale) {
      final ok = await tareScale();
      return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
    } else if (command.action == FeederAction.calibrateScale) {
      final ok = await calibrateScale(command.targetGrams);
      return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
    }
    return command.copyWith(status: CommandStatus.completed);
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _telemetryController.close();
    _connectionController.close();
    _logController.close();
  }
}
