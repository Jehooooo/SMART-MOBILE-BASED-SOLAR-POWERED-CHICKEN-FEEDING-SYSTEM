import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import '../../models/telemetry.dart';
import '../../models/schedule.dart';
import '../../models/feeding_log.dart';
import '../../models/feeder_command.dart';
import '../feeder_service.dart';
import 'hardware_adapter.dart';

/// Production Firebase Realtime Database Hardware Adapter.
///
/// Communicates with the physical ESP32 controller over Wi-Fi via Firebase:
/// - Listens to `/telemetry` (or `/feeders/{feederId}/telemetry`) for live sensor telemetry.
/// - Pushes feeding and diagnostic instructions to `/commands/dispense`.
/// - Syncs automated feeding routines to `/schedules`.
/// - Listens to `/logs` for completed closed-loop dispensing records.
/// - Features automatic REST HTTP fallback engine if native Firebase is not initialized.
class FirebaseHardwareAdapter implements FeederHardwareAdapter {
  final String feederId;
  final String databaseUrl;

  final _telemetryController = StreamController<FeederTelemetry>.broadcast();
  final _connectionController = StreamController<FeederConnection>.broadcast();
  final _logController = StreamController<FeedingLog>.broadcast();

  DatabaseReference? _rootRef;
  StreamSubscription<DatabaseEvent>? _telemetrySub;
  StreamSubscription<DatabaseEvent>? _logSub;
  StreamSubscription<DatabaseEvent>? _connectionSub;

  Timer? _restPollTimer;
  FeederConnection _currentConnection = FeederConnection.connecting;
  bool _isDispensing = false;

  FirebaseHardwareAdapter({
    this.feederId = '',
    this.databaseUrl =
        'https://smart-chicken-feeder-33bec-default-rtdb.asia-southeast1.firebasedatabase.app',
  });

  @override
  Stream<FeederTelemetry> get telemetryStream => _telemetryController.stream;

  @override
  Stream<FeederConnection> get connectionStream => _connectionController.stream;

  @override
  Stream<FeedingLog> get feedingLogStream => _logController.stream;

  @override
  String get hardwareSourceLabel => 'ESP32 Cloud (Firebase RTDB)';

  @override
  HardwareTransportType get transportType => HardwareTransportType.firebaseCloud;

  @override
  bool get isMock => false;

  @override
  Future<void> initialize() async {
    _connectionController.add(FeederConnection.connecting);

    // 1. Try native Firebase SDK if initialized
    if (Firebase.apps.isNotEmpty) {
      try {
        final db = databaseUrl.isNotEmpty
            ? FirebaseDatabase.instanceFor(
                app: Firebase.app(),
                databaseURL: databaseUrl,
              )
            : FirebaseDatabase.instance;

        _rootRef = (feederId.isEmpty || feederId == 'default' || feederId == 'root')
            ? db.ref()
            : db.ref('feeders/$feederId');

        // Monitor connection state
        _connectionSub = db.ref('.info/connected').onValue.listen((event) {
          final connected = event.snapshot.value as bool? ?? false;
          _currentConnection = connected ? FeederConnection.online : FeederConnection.offline;
          _connectionController.add(_currentConnection);
        });

        // Stream live telemetry
        _telemetrySub = _rootRef!.child('telemetry').onValue.listen((event) {
          final val = event.snapshot.value;
          if (val is Map) {
            final telemetry = FeederTelemetry.fromMap(val);
            _isDispensing = telemetry.status == FeederStatus.dispensing;
            _telemetryController.add(telemetry);
          }
        }, onError: (err) {
          debugPrint('Firebase telemetry stream error: $err');
        });

        // Stream logs
        _logSub = _rootRef!.child('logs').limitToLast(10).onChildAdded.listen((event) {
          final val = event.snapshot.value;
          if (val is Map) {
            final logId = event.snapshot.key ?? 'log_${DateTime.now().millisecondsSinceEpoch}';
            final log = FeedingLog.fromMap(logId, val);
            _logController.add(log);
          }
        });

        return;
      } catch (e) {
        debugPrint('Firebase native SDK fallback to REST: $e');
      }
    }

    // 2. Direct REST HTTP Synchronization Engine (cross-platform & zero GMS requirement)
    _startRestSyncEngine();
  }

  void _startRestSyncEngine() {
    _refreshRestTelemetry();
    _fetchRestLogs();
    _restPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _refreshRestTelemetry();
    });
  }

  String get _restBasePath {
    final cleanUrl = databaseUrl.endsWith('/')
        ? databaseUrl.substring(0, databaseUrl.length - 1)
        : databaseUrl;
    if (feederId.isNotEmpty && feederId != 'default' && feederId != 'root') {
      return '$cleanUrl/feeders/$feederId';
    }
    return cleanUrl;
  }

  Future<void> _refreshRestTelemetry() async {
    if (kIsWeb) return;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final uri = Uri.parse('$_restBasePath/telemetry.json');
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        if (body.isNotEmpty && body != 'null') {
          final map = jsonDecode(body);
          if (map is Map) {
            final telemetry = FeederTelemetry.fromMap(map);
            _isDispensing = telemetry.status == FeederStatus.dispensing;
            _telemetryController.add(telemetry);
            if (_currentConnection != FeederConnection.online) {
              _currentConnection = FeederConnection.online;
              _connectionController.add(FeederConnection.online);
            }
          }
        }
      } else {
        if (_currentConnection != FeederConnection.offline) {
          _currentConnection = FeederConnection.offline;
          _connectionController.add(FeederConnection.offline);
        }
      }
    } catch (e) {
      if (_currentConnection != FeederConnection.offline) {
        _currentConnection = FeederConnection.offline;
        _connectionController.add(FeederConnection.offline);
      }
    }
  }

  Future<void> _fetchRestLogs() async {
    if (kIsWeb) return;
    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final uri = Uri.parse('$_restBasePath/logs.json?orderBy="\$key"&limitToLast=10');
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        if (body.isNotEmpty && body != 'null') {
          final map = jsonDecode(body);
          if (map is Map) {
            for (final entry in map.entries) {
              if (entry.value is Map) {
                final log = FeedingLog.fromMap(entry.key.toString(), entry.value as Map);
                _logController.add(log);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('FirebaseHardwareAdapter REST logs error: $e');
    }
  }

  @override
  Future<bool> refreshTelemetry() async {
    if (_rootRef != null) {
      try {
        final snap = await _rootRef!.child('telemetry').get();
        if (snap.exists && snap.value is Map) {
          _telemetryController.add(FeederTelemetry.fromMap(snap.value as Map));
          return true;
        }
      } catch (e) {
        debugPrint('refreshTelemetry native error: $e');
      }
    }
    await _refreshRestTelemetry();
    return _currentConnection == FeederConnection.online;
  }

  @override
  Future<bool> triggerManualDispense({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (_isDispensing) return false;
    final cmd = FeederCommand(
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.dispense,
      durationSeconds: durationSeconds,
      targetGrams: targetGrams,
      timestamp: DateTime.now(),
      status: CommandStatus.pending,
    );

    // 1. Native Firebase write
    if (_rootRef != null) {
      try {
        await _rootRef!.child('commands/dispense').set(cmd.toJson());
        await _rootRef!.child('commands/latest').set(cmd.toJson());
        return true;
      } catch (e) {
        debugPrint('triggerManualDispense native error: $e');
      }
    }

    // 2. REST HTTP fallback
    if (!kIsWeb) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        final request = await client.putUrl(Uri.parse('$_restBasePath/commands/dispense.json'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(cmd.toJson()));
        final response = await request.close();
        return response.statusCode == 200;
      } catch (e) {
        debugPrint('triggerManualDispense REST error: $e');
      }
    }
    return false;
  }

  @override
  Future<void> cancelDispense() async {
    final payload = {
      'id': 'cmd_stop_${DateTime.now().millisecondsSinceEpoch}',
      'action': 'STOP',
      'durationSeconds': 0,
      'targetGrams': 0.0,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'status': 'pending',
    };

    if (_rootRef != null) {
      try {
        await _rootRef!.child('commands/dispense').set(payload);
        return;
      } catch (e) {
        debugPrint('cancelDispense native error: $e');
      }
    }

    if (!kIsWeb) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 3);
        final request = await client.putUrl(Uri.parse('$_restBasePath/commands/dispense.json'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(payload));
        await request.close();
      } catch (e) {
        debugPrint('cancelDispense REST error: $e');
      }
    }
  }

  @override
  Future<bool> syncSchedules(List<FeedingSchedule> schedules) async {
    final map = {
      for (final s in schedules) s.id: s.toMap(),
    };

    if (_rootRef != null) {
      try {
        await _rootRef!.child('schedules').set(map);
        return true;
      } catch (e) {
        debugPrint('syncSchedules native error: $e');
      }
    }

    if (!kIsWeb) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        final request = await client.putUrl(Uri.parse('$_restBasePath/schedules.json'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(schedules.map((s) => s.toMap()).toList()));
        final response = await request.close();
        return response.statusCode == 200;
      } catch (e) {
        debugPrint('syncSchedules REST error: $e');
      }
    }
    return false;
  }

  @override
  Future<FeederCommand> sendCommand(FeederCommand command) async {
    final jsonPayload = command.toJson();

    if (_rootRef != null) {
      try {
        await _rootRef!.child('commands/dispense').set(jsonPayload);
        await _rootRef!.child('commands/${command.id}').set(jsonPayload);
        return command.copyWith(status: CommandStatus.completed);
      } catch (e) {
        debugPrint('sendCommand native error: $e');
      }
    }

    if (!kIsWeb) {
      try {
        final client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 4);
        final request = await client.putUrl(Uri.parse('$_restBasePath/commands/dispense.json'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(jsonPayload));
        final response = await request.close();
        if (response.statusCode == 200) {
          return command.copyWith(status: CommandStatus.completed);
        }
      } catch (e) {
        return command.copyWith(
          status: CommandStatus.failed,
          errorMessage: e.toString(),
        );
      }
    }

    return command.copyWith(
      status: CommandStatus.failed,
      errorMessage: 'Database connection failed',
    );
  }

  /// Sends a zero-tare command to the HX711 load cell via Firebase commands/dispense.
  Future<bool> tareScale() async {
    final cmd = FeederCommand(
      id: 'cmd_tare_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.tareScale,
      durationSeconds: 0,
      targetGrams: 0.0,
      timestamp: DateTime.now(),
    );
    final res = await sendCommand(cmd);
    return res.status == CommandStatus.completed;
  }

  /// Sends a known-weight reference factor calibration command to the load cell.
  Future<bool> calibrateScale(double knownGrams) async {
    final cmd = FeederCommand(
      id: 'cmd_cal_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.calibrateScale,
      durationSeconds: 0,
      targetGrams: knownGrams,
      timestamp: DateTime.now(),
    );
    final res = await sendCommand(cmd);
    return res.status == CommandStatus.completed;
  }

  @override
  void dispose() {
    _restPollTimer?.cancel();
    _telemetrySub?.cancel();
    _logSub?.cancel();
    _connectionSub?.cancel();
    _telemetryController.close();
    _connectionController.close();
    _logController.close();
  }
}

