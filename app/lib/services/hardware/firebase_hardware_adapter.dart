import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/telemetry.dart';
import '../../models/schedule.dart';
import '../../models/feeding_log.dart';
import '../../models/feeder_command.dart';
import '../feeder_service.dart';
import 'hardware_adapter.dart';

/// Production Firebase Realtime Database Hardware Adapter.
///
/// Communicates with the physical ESP32 controller or cloud simulator over Wi-Fi via Firebase:
/// - Listens to `/telemetry` (or `/feeders/{feederId}/telemetry`) for live sensor telemetry.
/// - Pushes feeding and diagnostic instructions to `/commands/dispense` and emergency stop to `/commands/stop`.
/// - Reads `/commands/latest` for hardware command execution acknowledgements.
/// - Syncs automated feeding routines to `/schedules`.
/// - Listens to `/logs` for completed closed-loop dispensing records.
/// - Supports both native FlutterFire SDK and authenticated cross-platform REST HTTP sync.
class FirebaseHardwareAdapter implements FeederHardwareAdapter {
  final String feederId;
  final String databaseUrl;
  final String apiKey;
  final String authEmail;
  final String authPassword;
  final Future<String?> Function()? authTokenProvider;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

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
  bool _isCommandInFlight = false;
  bool _disposed = false;
  String? _lastErrorMessage;
  String? _cachedIdToken;
  DateTime? _tokenExpiry;
  final Set<String> _seenLogIds = <String>{};

  FirebaseHardwareAdapter({
    this.feederId = '',
    this.databaseUrl =
        'https://smart-chicken-feeder-33bec-default-rtdb.asia-southeast1.firebasedatabase.app',
    this.apiKey = const String.fromEnvironment('FIREBASE_API_KEY'),
    this.authEmail = const String.fromEnvironment('FIREBASE_USER_EMAIL'),
    this.authPassword = const String.fromEnvironment('FIREBASE_USER_PASSWORD'),
    this.authTokenProvider,
    http.Client? httpClient,
  })  : _httpClient = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null;

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

  /// Latest Firebase communication/permission error message, if any.
  String? get lastErrorMessage => _lastErrorMessage;

  void _emitTelemetry(FeederTelemetry telemetry) {
    if (!_disposed && !_telemetryController.isClosed) {
      _telemetryController.add(telemetry);
    }
  }

  void _emitConnection(FeederConnection state) {
    if (_currentConnection != state) {
      _currentConnection = state;
      if (!_disposed && !_connectionController.isClosed) {
        _connectionController.add(state);
      }
    }
  }

  void _emitLog(FeedingLog log) {
    if (!_disposed && !_logController.isClosed) {
      _logController.add(log);
    }
  }

  Future<void> _cancelActiveListeners() async {
    _restPollTimer?.cancel();
    _restPollTimer = null;
    await _telemetrySub?.cancel();
    _telemetrySub = null;
    await _logSub?.cancel();
    _logSub = null;
    await _connectionSub?.cancel();
    _connectionSub = null;
    _rootRef = null;
  }

  @override
  Future<void> initialize() async {
    if (_disposed) return;
    await _cancelActiveListeners();

    _currentConnection = FeederConnection.connecting;
    if (!_connectionController.isClosed) {
      _connectionController.add(FeederConnection.connecting);
    }

    // 1. Try native Firebase SDK if initialized on a supported mobile/web platform
    final supportsNativeRtdb = kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    if (supportsNativeRtdb && Firebase.apps.isNotEmpty) {
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
          _emitConnection(connected ? FeederConnection.online : FeederConnection.offline);
        }, onError: (err) {
          _lastErrorMessage = 'Firebase connection monitor error: $err';
          debugPrint(_lastErrorMessage);
          _emitConnection(FeederConnection.offline);
        });

        // Stream live telemetry
        _telemetrySub = _rootRef!.child('telemetry').onValue.listen((event) {
          final val = event.snapshot.value;
          if (val is Map) {
            final telemetry = FeederTelemetry.fromMap(val);
            _isDispensing = telemetry.status == FeederStatus.dispensing;
            _lastErrorMessage = null;
            _emitTelemetry(telemetry);
          }
        }, onError: (err) {
          _lastErrorMessage = 'Firebase telemetry permission/stream error: $err';
          debugPrint(_lastErrorMessage);
          _emitConnection(FeederConnection.offline);
        });

        // Stream logs
        _logSub = _rootRef!.child('logs').limitToLast(25).onChildAdded.listen((event) {
          final val = event.snapshot.value;
          if (val is Map) {
            final logId = event.snapshot.key ?? 'log_${DateTime.now().millisecondsSinceEpoch}';
            if (_seenLogIds.add(logId)) {
              final log = FeedingLog.fromMap(logId, val);
              _emitLog(log);
            }
          }
        }, onError: (err) {
          debugPrint('Firebase log stream error: $err');
        });

        return;
      } catch (e) {
        debugPrint('Firebase native SDK fallback to REST: $e');
        await _cancelActiveListeners();
      }
    }

    // 2. Direct REST HTTP Synchronization Engine (universal cross-platform)
    _startRestSyncEngine();
  }

  void _startRestSyncEngine() {
    _refreshRestTelemetry();
    _fetchRestLogs();
    _restPollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_disposed) {
        _refreshRestTelemetry();
        _fetchRestLogs();
      }
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

  Future<String?> _resolveAuthToken({bool forceRefresh = false}) async {
    if (authTokenProvider != null) {
      try {
        final token = await authTokenProvider!();
        if (token != null && token.isNotEmpty) return token;
      } catch (e) {
        debugPrint('Custom authTokenProvider error: $e');
      }
    }

    if (Firebase.apps.isNotEmpty) {
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          final token = await user.getIdToken(forceRefresh);
          if (token != null && token.isNotEmpty) return token;
        }
      } catch (e) {
        debugPrint('FirebaseAuth getIdToken fallback: $e');
      }
    }

    if (apiKey.isEmpty) return null;

    if (!forceRefresh &&
        _cachedIdToken != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!)) {
      return _cachedIdToken;
    }

    final usePasswordAuth = authEmail.isNotEmpty && authPassword.isNotEmpty;
    final endpoint = usePasswordAuth
        ? 'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$apiKey'
        : 'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$apiKey';
    final payload = usePasswordAuth
        ? {
            'email': authEmail,
            'password': authPassword,
            'returnSecureToken': true,
          }
        : {'returnSecureToken': true};

    try {
      final resp = await _httpClient
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final decoded = jsonDecode(resp.body);
        if (decoded is Map && decoded['idToken'] is String) {
          _cachedIdToken = decoded['idToken'] as String;
          final expiresSec = int.tryParse('${decoded['expiresIn'] ?? '3600'}') ?? 3600;
          _tokenExpiry = DateTime.now().add(Duration(seconds: (expiresSec - 300).clamp(60, 3600)));
          return _cachedIdToken;
        }
      } else {
        debugPrint('IdentityToolkit auth failed (HTTP ${resp.statusCode})');
      }
    } catch (e) {
      debugPrint('IdentityToolkit auth network error: $e');
    }
    return null;
  }

  Future<Uri> _authorizedUri(String relativePath, {bool forceRefreshToken = false}) async {
    final raw = '$_restBasePath/$relativePath';
    final baseUri = Uri.parse(raw);
    final token = await _resolveAuthToken(forceRefresh: forceRefreshToken);
    if (token == null || token.isEmpty) {
      return baseUri;
    }
    final qp = Map<String, String>.from(baseUri.queryParameters);
    qp['auth'] = token;
    return baseUri.replace(queryParameters: qp);
  }

  bool _recordHttpErrorIfDenied(http.Response response, String operation) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      _lastErrorMessage =
          'Firebase permission denied during $operation (HTTP ${response.statusCode}). Authenticate client or check RTDB security rules.';
      _emitConnection(FeederConnection.offline);
      return true;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _lastErrorMessage = 'Firebase $operation failed (HTTP ${response.statusCode}).';
      return true;
    }
    _lastErrorMessage = null;
    return false;
  }

  Future<void> _refreshRestTelemetry() async {
    if (_disposed) return;
    try {
      var response = await _httpClient
          .get(await _authorizedUri('telemetry.json'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 401 && apiKey.isNotEmpty) {
        response = await _httpClient
            .get(await _authorizedUri('telemetry.json', forceRefreshToken: true))
            .timeout(const Duration(seconds: 4));
      }

      if (!_recordHttpErrorIfDenied(response, 'telemetry read')) {
        final body = response.body;
        if (body.isNotEmpty && body != 'null') {
          final map = jsonDecode(body);
          if (map is Map) {
            final telemetry = FeederTelemetry.fromMap(map);
            _isDispensing = telemetry.status == FeederStatus.dispensing;
            _emitTelemetry(telemetry);
            _emitConnection(FeederConnection.online);
            return;
          }
        }
      }
      _emitConnection(FeederConnection.offline);
    } catch (e) {
      _lastErrorMessage = 'Firebase network unreachable: $e';
      _emitConnection(FeederConnection.offline);
    }
  }

  Future<void> _fetchRestLogs() async {
    if (_disposed) return;
    try {
      final response = await _httpClient
          .get(await _authorizedUri('logs.json'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final body = response.body;
        if (body.isNotEmpty && body != 'null') {
          final map = jsonDecode(body);
          if (map is Map) {
            for (final entry in map.entries) {
              final logId = entry.key.toString();
              if (_seenLogIds.add(logId) && entry.value is Map) {
                final log = FeedingLog.fromMap(logId, entry.value as Map);
                _emitLog(log);
              }
            }
          }
        }
      } else {
        _recordHttpErrorIfDenied(response, 'logs read');
      }
    } catch (e) {
      debugPrint('FirebaseHardwareAdapter REST logs error: $e');
    }
  }

  /// Fetches all feeding logs stored in Firebase RTDB `/logs.json`.
  /// Returns `null` if the network or permission check failed, or an empty list if the node is empty.
  Future<List<FeedingLog>?> fetchLogsSnapshot() async {
    if (_rootRef != null) {
      try {
        final snap = await _rootRef!.child('logs').get();
        if (!snap.exists || snap.value == null) return <FeedingLog>[];
        if (snap.value is Map) {
          final list = <FeedingLog>[];
          for (final entry in (snap.value as Map).entries) {
            if (entry.value is Map) {
              final id = entry.key.toString();
              _seenLogIds.add(id);
              list.add(FeedingLog.fromMap(id, entry.value as Map));
            }
          }
          list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return list;
        }
      } catch (e) {
        _lastErrorMessage = 'Firebase native logs read failed: $e';
      }
    }

    try {
      final response = await _httpClient
          .get(await _authorizedUri('logs.json'))
          .timeout(const Duration(seconds: 4));
      if (_recordHttpErrorIfDenied(response, 'logs sync')) {
        return null;
      }
      final body = response.body;
      if (body.isEmpty || body == 'null') return <FeedingLog>[];
      final data = jsonDecode(body);
      final list = <FeedingLog>[];
      if (data is Map) {
        for (final entry in data.entries) {
          if (entry.value is Map) {
            final id = entry.key.toString();
            _seenLogIds.add(id);
            list.add(FeedingLog.fromMap(id, entry.value as Map));
          }
        }
      }
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    } catch (e) {
      _lastErrorMessage = 'Firebase logs sync error: $e';
      debugPrint(_lastErrorMessage);
      return null;
    }
  }

  /// Fetches schedules configured in Firebase RTDB `/schedules.json`.
  /// Returns `null` if the HTTP/permission request failed, or a list (possibly empty) on HTTP 200.
  Future<List<FeedingSchedule>?> fetchSchedulesSnapshot() async {
    if (_rootRef != null) {
      try {
        final snap = await _rootRef!.child('schedules').get();
        if (!snap.exists || snap.value == null) return <FeedingSchedule>[];
        return _parseScheduleData(snap.value);
      } catch (e) {
        _lastErrorMessage = 'Firebase native schedules read failed: $e';
      }
    }

    try {
      final response = await _httpClient
          .get(await _authorizedUri('schedules.json'))
          .timeout(const Duration(seconds: 4));
      if (_recordHttpErrorIfDenied(response, 'schedules read')) {
        return null;
      }
      final body = response.body;
      if (body.isEmpty || body == 'null') return <FeedingSchedule>[];
      return _parseScheduleData(jsonDecode(body));
    } catch (e) {
      _lastErrorMessage = 'Firebase schedules sync error: $e';
      debugPrint(_lastErrorMessage);
      return null;
    }
  }

  List<FeedingSchedule> _parseScheduleData(dynamic data) {
    final list = <FeedingSchedule>[];
    if (data is Map) {
      for (final entry in data.entries) {
        if (entry.value is Map) {
          list.add(FeedingSchedule.fromMap(entry.key.toString(), entry.value as Map));
        }
      }
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        if (data[i] is Map) {
          final id = data[i]['id']?.toString() ?? 'sch_$i';
          list.add(FeedingSchedule.fromMap(id, data[i] as Map));
        }
      }
    }
    return list;
  }

  /// Fetches schedules configured in Firebase RTDB (legacy list convenience wrapper).
  Future<List<FeedingSchedule>> fetchSchedules() async {
    return (await fetchSchedulesSnapshot()) ?? <FeedingSchedule>[];
  }

  /// Reads `/commands/latest.json` to inspect controller acknowledgement (`inProgress`, `completed`, `aborted`, `failed`).
  Future<FeederCommand?> fetchLatestCommandStatus() async {
    if (_rootRef != null) {
      try {
        final snap = await _rootRef!.child('commands/latest').get();
        if (snap.exists && snap.value is Map) {
          final map = Map<String, dynamic>.from(snap.value as Map);
          return FeederCommand.fromJson(map);
        }
      } catch (e) {
        debugPrint('fetchLatestCommandStatus native error: $e');
      }
    }

    try {
      final response = await _httpClient
          .get(await _authorizedUri('commands/latest.json'))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200 &&
          response.body.isNotEmpty &&
          response.body != 'null') {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          return FeederCommand.fromJson(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (e) {
      debugPrint('fetchLatestCommandStatus REST error: $e');
    }
    return null;
  }

  /// Writes a feeding log entry directly to Firebase RTDB `/logs/{id}`.
  Future<bool> saveFeedingLog(FeedingLog log) async {
    _seenLogIds.add(log.id);
    if (_rootRef != null) {
      try {
        await _rootRef!.child('logs/${log.id}').set({
          'id': log.id,
          ...log.toMap(),
        });
        _lastErrorMessage = null;
        return true;
      } catch (e) {
        debugPrint('saveFeedingLog native error: $e');
      }
    }
    try {
      final response = await _httpClient
          .put(
            await _authorizedUri('logs/${log.id}.json'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': log.id,
              ...log.toMap(),
            }),
          )
          .timeout(const Duration(seconds: 4));
      return !_recordHttpErrorIfDenied(response, 'log write');
    } catch (e) {
      _lastErrorMessage = 'saveFeedingLog REST error: $e';
      debugPrint(_lastErrorMessage);
      return false;
    }
  }

  @override
  Future<bool> refreshTelemetry() async {
    if (_disposed) return false;
    if (_rootRef != null) {
      try {
        final snap = await _rootRef!.child('telemetry').get();
        if (snap.exists && snap.value is Map) {
          final telemetry = FeederTelemetry.fromMap(snap.value as Map);
          _isDispensing = telemetry.status == FeederStatus.dispensing;
          _lastErrorMessage = null;
          _emitTelemetry(telemetry);
          _emitConnection(FeederConnection.online);
          return true;
        }
      } catch (e) {
        _lastErrorMessage = 'refreshTelemetry native error: $e';
        debugPrint(_lastErrorMessage);
      }
    }
    await _refreshRestTelemetry();
    await _fetchRestLogs();
    return _currentConnection == FeederConnection.online;
  }

  Future<bool> _dispatchPendingCommandMap(Map<String, dynamic> payload, String operation) async {
    if (_rootRef != null) {
      try {
        await _rootRef!.child('commands/dispense').set(payload);
        await _rootRef!.child('commands/latest').set(payload);
        _lastErrorMessage = null;
        return true;
      } catch (e) {
        debugPrint('$operation native error: $e');
      }
    }

    try {
      final response = await _httpClient
          .put(
            await _authorizedUri('commands/dispense.json'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 4));
      if (_recordHttpErrorIfDenied(response, operation)) {
        return false;
      }
      // Best-effort mirror to /commands/latest.json for status tracking
      unawaited(_httpClient
          .put(
            await _authorizedUri('commands/latest.json'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 3))
          .catchError((_) => http.Response('', 500)));
      return true;
    } catch (e) {
      _lastErrorMessage = '$operation REST error: $e';
      debugPrint(_lastErrorMessage);
      return false;
    }
  }

  @override
  Future<bool> triggerManualDispense({int durationSeconds = 5, double targetGrams = 0.0}) async {
    if (_isDispensing || _isCommandInFlight) return false;
    _isCommandInFlight = true;
    try {
      final clampedSec = durationSeconds.clamp(1, 60);
      final effectiveTarget = targetGrams > 0 ? targetGrams : (clampedSec * 20.0);
      final cmd = FeederCommand(
        id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
        action: FeederAction.dispense,
        durationSeconds: clampedSec,
        targetGrams: effectiveTarget,
        triggerType: 'Manual',
        timestamp: DateTime.now(),
        status: CommandStatus.pending,
      );
      return await _dispatchPendingCommandMap(cmd.toJson(), 'manual dispense');
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Triggers a scheduled routine dispense on the hardware.
  @override
  Future<bool> triggerScheduleDispense(FeedingSchedule schedule) async {
    if (_isDispensing || _isCommandInFlight) return false;
    _isCommandInFlight = true;
    try {
      final now = DateTime.now();
      final slotKey = '${now.year}-${now.month}-${now.day}_${now.hour}:${now.minute}_${schedule.id}';
      final cmd = FeederCommand(
        id: 'cmd_sch_${now.millisecondsSinceEpoch}',
        action: FeederAction.dispense,
        durationSeconds: schedule.durationSeconds.clamp(1, 60),
        targetGrams: schedule.targetGrams,
        triggerType: 'Schedule (${schedule.label})',
        scheduleSlotKey: slotKey,
        timestamp: now,
        status: CommandStatus.pending,
      );
      return await _dispatchPendingCommandMap(cmd.toJson(), 'schedule dispense');
    } finally {
      _isCommandInFlight = false;
    }
  }

  @override
  Future<void> cancelDispense() async {
    _isDispensing = false;
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
        await Future.wait([
          _rootRef!.child('commands/stop').set(payload),
          _rootRef!.child('commands/dispense').set(payload),
        ]);
        return;
      } catch (e) {
        debugPrint('cancelDispense native error: $e');
      }
    }

    try {
      final body = jsonEncode(payload);
      await Future.wait([
        _httpClient
            .put(
              await _authorizedUri('commands/stop.json'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 3)),
        _httpClient
            .put(
              await _authorizedUri('commands/dispense.json'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 3)),
      ]);
    } catch (e) {
      debugPrint('cancelDispense REST error: $e');
    }
  }

  @override
  Future<bool> syncSchedules(List<FeedingSchedule> schedules) async {
    if (schedules.isEmpty) {
      if (_rootRef != null) {
        try {
          await _rootRef!.child('schedules').remove();
          _lastErrorMessage = null;
          return true;
        } catch (e) {
          debugPrint('syncSchedules native remove error: $e');
        }
      }
      try {
        final response = await _httpClient
            .delete(await _authorizedUri('schedules.json'))
            .timeout(const Duration(seconds: 4));
        return !_recordHttpErrorIfDenied(response, 'schedules clear');
      } catch (e) {
        _lastErrorMessage = 'syncSchedules REST remove error: $e';
        debugPrint(_lastErrorMessage);
        return false;
      }
    }

    final map = {
      for (final s in schedules)
        s.id: {
          'id': s.id,
          ...s.toMap(),
        },
    };

    if (_rootRef != null) {
      try {
        await _rootRef!.child('schedules').set(map);
        _lastErrorMessage = null;
        return true;
      } catch (e) {
        debugPrint('syncSchedules native error: $e');
      }
    }

    try {
      final response = await _httpClient
          .put(
            await _authorizedUri('schedules.json'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(map),
          )
          .timeout(const Duration(seconds: 4));
      return !_recordHttpErrorIfDenied(response, 'schedules write');
    } catch (e) {
      _lastErrorMessage = 'syncSchedules REST error: $e';
      debugPrint(_lastErrorMessage);
      return false;
    }
  }

  @override
  Future<FeederCommand> sendCommand(FeederCommand command) async {
    if (command.action == FeederAction.emergencyStop) {
      await cancelDispense();
      return command.copyWith(status: CommandStatus.completed);
    }

    if (_isCommandInFlight) {
      return command.copyWith(
        status: CommandStatus.failed,
        errorMessage: 'Another hardware command is already in flight.',
      );
    }

    _isCommandInFlight = true;
    try {
      final ok = await _dispatchPendingCommandMap(command.toJson(), command.action.commandString);
      if (ok) {
        return command.copyWith(status: CommandStatus.completed);
      }
      return command.copyWith(
        status: CommandStatus.failed,
        errorMessage: _lastErrorMessage ?? 'Database connection failed',
      );
    } finally {
      _isCommandInFlight = false;
    }
  }

  /// Sends a zero-tare command to the HX711 load cell via Firebase `/commands/dispense`.
  Future<bool> tareScale() async {
    final cmd = FeederCommand.tareScale();
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

  /// Sends a direct servo angle test command (`SERVO_TEST`, `0..90` degrees).
  Future<bool> testServoGate(int angleDegrees) async {
    final cmd = FeederCommand.servoTest(angleDegrees);
    final res = await sendCommand(cmd);
    return res.status == CommandStatus.completed;
  }

  @override
  void dispose() {
    _disposed = true;
    _restPollTimer?.cancel();
    _telemetrySub?.cancel();
    _logSub?.cancel();
    _connectionSub?.cancel();
    if (_ownsHttpClient) {
      _httpClient.close();
    }
    _telemetryController.close();
    _connectionController.close();
    _logController.close();
  }
}
