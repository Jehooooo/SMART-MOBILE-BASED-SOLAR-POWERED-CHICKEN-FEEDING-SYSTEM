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
/// - `POST /api/servo` -> tests MG996R gate angle (`0..90`)
/// - `POST /api/schedules` -> synchronizes schedule table to onboard NVS/RTC
/// - `GET /api/logs` -> retrieves onboard ring-buffered feeding logs
class RestHardwareAdapter implements FeederHardwareAdapter {
  final String host;
  final int port;

  final _telemetryController = StreamController<FeederTelemetry>.broadcast();
  final _connectionController = StreamController<FeederConnection>.broadcast();
  final _logController = StreamController<FeedingLog>.broadcast();

  Timer? _pollTimer;
  HttpClient? _httpClient;
  FeederConnection _currentConnection = FeederConnection.connecting;
  bool _isDispensing = false;
  bool _isCommandInFlight = false;
  bool _disposed = false;
  DateTime? _lastAutoClockSyncAt;
  final Set<String> _seenLogIds = <String>{};

  RestHardwareAdapter({
    this.host = '192.168.4.1', // Default ESP32 SoftAP IP
    this.port = 80,
  });

  String get _baseUrl => 'http://$host:$port';

  HttpClient _ensureClient() {
    final existing = _httpClient;
    if (existing != null) return existing;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    _httpClient = client;
    return client;
  }

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
    if (_disposed) return;
    _pollTimer?.cancel();
    if (!_connectionController.isClosed) {
      _connectionController.add(FeederConnection.connecting);
    }
    await refreshTelemetry();
    await _fetchLocalLogs();

    // Poll every 3 seconds when connected
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_disposed) {
        refreshTelemetry();
        _fetchLocalLogs();
      }
    });
  }

  @override
  Future<bool> refreshTelemetry() async {
    if (kIsWeb || _disposed) return false;
    try {
      final client = _ensureClient();
      final request = await client
          .getUrl(Uri.parse('$_baseUrl/api/telemetry'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final map = jsonDecode(body) as Map<dynamic, dynamic>;
        var telemetry = FeederTelemetry.fromMap(map);

        // When operating purely off-grid without NTP/RTC epoch sync, ESP32 reports
        // `millis()` uptime (< year 2000). A live direct TCP HTTP 200 proves the
        // controller is online right now, so normalize its heartbeat to wall-clock now.
        final rawHb = (map['lastHeartbeat'] as num?)?.toInt() ?? 0;
        if (rawHb < 946684800000) {
          final now = DateTime.now();
          telemetry = telemetry.copyWith(lastHeartbeat: now);
          if (_lastAutoClockSyncAt == null ||
              now.difference(_lastAutoClockSyncAt!) >= const Duration(seconds: 30)) {
            _lastAutoClockSyncAt = now;
            unawaited(syncClock(now));
          }
        }

        _isDispensing = telemetry.status == FeederStatus.dispensing;
        if (!_disposed && !_telemetryController.isClosed) {
          _telemetryController.add(telemetry);
        }
        _setConnection(FeederConnection.online);
        return true;
      } else {
        await response.drain<void>();
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
      if (!_disposed && !_connectionController.isClosed) {
        _connectionController.add(_currentConnection);
      }
    }
  }

  Future<bool> _postJson(String path, Map<String, dynamic>? bodyMap) async {
    if (kIsWeb || _disposed) return false;
    try {
      final client = _ensureClient();
      final request = await client
          .postUrl(Uri.parse('$_baseUrl$path'))
          .timeout(const Duration(seconds: 2));
      if (bodyMap != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(bodyMap));
      }
      final response = await request.close().timeout(const Duration(seconds: 3));
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('RestHardwareAdapter POST $path error: $e');
      return false;
    }
  }

  @override
  Future<bool> triggerManualDispense({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (kIsWeb || _isDispensing || _isCommandInFlight) return false;
    _isCommandInFlight = true;
    try {
      return await _postJson('/api/dispense', {
        'durationSeconds': durationSeconds.clamp(1, 60),
        'duration': durationSeconds.clamp(1, 60),
        'targetGrams': targetGrams,
      });
    } finally {
      _isCommandInFlight = false;
    }
  }

  @override
  Future<bool> triggerScheduleDispense(FeedingSchedule schedule) async {
    return triggerManualDispense(
      durationSeconds: schedule.durationSeconds,
      targetGrams: schedule.targetGrams,
    );
  }

  @override
  Future<void> cancelDispense() async {
    if (kIsWeb || _disposed) return;
    _isDispensing = false;
    await _postJson('/api/stop', null);
  }

  @override
  Future<bool> syncSchedules(List<FeedingSchedule> schedules) async {
    if (kIsWeb || _disposed) return false;
    try {
      final client = _ensureClient();
      final request = await client
          .postUrl(Uri.parse('$_baseUrl/api/schedules'))
          .timeout(const Duration(seconds: 2));
      request.headers.contentType = ContentType.json;
      final payload = schedules.map((s) => {'id': s.id, ...s.toMap()}).toList();
      request.write(jsonEncode(payload));
      final response = await request.close().timeout(const Duration(seconds: 3));
      await response.drain<void>();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('RestHardwareAdapter sync error: $e');
      return false;
    }
  }

  Future<bool> tareScale() async {
    if (_isCommandInFlight) return false;
    _isCommandInFlight = true;
    try {
      return await _postJson('/api/tare', null);
    } finally {
      _isCommandInFlight = false;
    }
  }

  Future<bool> clearFault() async {
    if (_isCommandInFlight) return false;
    _isCommandInFlight = true;
    try {
      return await _postJson('/api/clear-fault', null);
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Fetches onboard schedules stored in ESP32 NVS (`GET /api/schedules`).
  Future<List<FeedingSchedule>?> fetchSchedulesSnapshot() async {
    if (kIsWeb || _disposed) return null;
    try {
      final client = _ensureClient();
      final request = await client
          .getUrl(Uri.parse('$_baseUrl/api/schedules'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      if (body.isEmpty || body == 'null') return <FeedingSchedule>[];
      final decoded = jsonDecode(body);
      final list = <FeedingSchedule>[];
      if (decoded is List) {
        for (var i = 0; i < decoded.length; i++) {
          final item = decoded[i];
          if (item is Map) {
            final id = item['id']?.toString() ?? 'sch_$i';
            list.add(FeedingSchedule.fromMap(id, item));
          }
        }
      } else if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            list.add(FeedingSchedule.fromMap(entry.key.toString(), entry.value as Map));
          }
        }
      }
      return list;
    } catch (e) {
      debugPrint('RestHardwareAdapter fetchSchedulesSnapshot error: $e');
      return null;
    }
  }

  /// Fetches onboard ring-buffered feeding logs from ESP32 (`GET /api/logs`).
  Future<List<FeedingLog>?> fetchLogsSnapshot() async {
    if (kIsWeb || _disposed) return null;
    try {
      final client = _ensureClient();
      final request = await client
          .getUrl(Uri.parse('$_baseUrl/api/logs'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode != 200) {
        await response.drain<void>();
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      if (body.isEmpty || body == 'null') return <FeedingLog>[];
      final decoded = jsonDecode(body);
      final list = <FeedingLog>[];
      if (decoded is List) {
        for (var i = 0; i < decoded.length; i++) {
          final item = decoded[i];
          if (item is Map) {
            final id = item['id']?.toString() ?? 'log_local_$i';
            _seenLogIds.add(id);
            list.add(FeedingLog.fromMap(id, item));
          }
        }
      }
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      debugPrint('RestHardwareAdapter fetchLogsSnapshot error: $e');
      return null;
    }
  }

  Future<void> _fetchLocalLogs() async {
    if (kIsWeb || _disposed || _currentConnection != FeederConnection.online) return;
    try {
      final client = _ensureClient();
      final request = await client
          .getUrl(Uri.parse('$_baseUrl/api/logs'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        if (body.isNotEmpty && body != 'null') {
          final decoded = jsonDecode(body);
          if (decoded is List) {
            for (var i = 0; i < decoded.length; i++) {
              final item = decoded[i];
              if (item is Map) {
                final id = item['id']?.toString() ?? 'log_local_$i';
                if (_seenLogIds.add(id) && !_disposed && !_logController.isClosed) {
                  _logController.add(FeedingLog.fromMap(id, item));
                }
              }
            }
          }
        }
      } else {
        await response.drain<void>();
      }
    } catch (_) {}
  }

  /// Queries ESP32 Wi-Fi station/AP status (`GET http://192.168.4.1/api/wifi`).
  static Future<Map<String, dynamic>?> querySoftApWifiStatus({
    String host = '192.168.4.1',
    int port = 80,
  }) async {
    if (kIsWeb) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client
          .getUrl(Uri.parse('http://$host:$port/api/wifi'))
          .timeout(const Duration(seconds: 2));
      final resp = await req.close().timeout(const Duration(seconds: 3));
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final decoded = jsonDecode(body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } else {
        await resp.drain<void>();
      }
    } catch (_) {
    } finally {
      client.close(force: true);
    }
    return null;
  }

  /// Sends client 2.4 GHz Wi-Fi credentials to ESP32 NVS (`POST http://192.168.4.1/api/wifi`).
  static Future<Map<String, dynamic>?> provisionSoftApWifi({
    required String ssid,
    required String password,
    String host = '192.168.4.1',
    int port = 80,
  }) async {
    if (kIsWeb || ssid.trim().isEmpty) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final req = await client
          .postUrl(Uri.parse('http://$host:$port/api/wifi'))
          .timeout(const Duration(seconds: 3));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'ssid': ssid.trim(), 'password': password}));
      final resp = await req.close().timeout(const Duration(seconds: 9));
      final body = await resp.transform(utf8.decoder).join();
      if (resp.statusCode == 200 && body.isNotEmpty) {
        final decoded = jsonDecode(body);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('provisionSoftApWifi error: $e');
    } finally {
      client.close(force: true);
    }
    return null;
  }

  Future<bool> calibrateScale(double knownGrams) async {
    if (_isCommandInFlight) return false;
    _isCommandInFlight = true;
    try {
      return await _postJson('/api/calibrate', {'targetGrams': knownGrams});
    } finally {
      _isCommandInFlight = false;
    }
  }

  Future<bool> testServoGate(int angleDegrees) async {
    if (_isCommandInFlight) return false;
    _isCommandInFlight = true;
    try {
      return await _postJson('/api/servo', {
        'servoAngle': angleDegrees.clamp(0, 90),
        'angle': angleDegrees.clamp(0, 90),
      });
    } finally {
      _isCommandInFlight = false;
    }
  }

  Future<bool> syncClock(DateTime now) async {
    return _postJson('/api/sync-clock', {'timestamp': now.millisecondsSinceEpoch});
  }

  @override
  Future<FeederCommand> sendCommand(FeederCommand command) async {
    switch (command.action) {
      case FeederAction.dispense:
        final ok = await triggerManualDispense(
          durationSeconds: command.durationSeconds,
          targetGrams: command.targetGrams,
        );
        return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
      case FeederAction.emergencyStop:
        await cancelDispense();
        return command.copyWith(status: CommandStatus.completed);
      case FeederAction.tareScale:
        final ok = await tareScale();
        return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
      case FeederAction.clearFault:
        final ok = await clearFault();
        return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
      case FeederAction.calibrateScale:
        final ok = await calibrateScale(command.targetGrams);
        return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
      case FeederAction.setServoAngle:
        final ok = await testServoGate(command.servoAngle ?? 0);
        return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
      case FeederAction.syncClock:
        final ok = await syncClock(command.timestamp);
        return command.copyWith(status: ok ? CommandStatus.completed : CommandStatus.failed);
      case FeederAction.restartController:
        return command.copyWith(status: CommandStatus.completed);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _httpClient?.close(force: true);
    _httpClient = null;
    _telemetryController.close();
    _connectionController.close();
    _logController.close();
  }
}
