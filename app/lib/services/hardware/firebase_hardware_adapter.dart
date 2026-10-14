import 'dart:async';
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
/// - Listens to `/feeders/{feederId}/telemetry` for live sensor telemetry (level, battery, scale, status).
/// - Pushes manual feeding instructions to `/feeders/{feederId}/commands`.
/// - Syncs automated feeding routines to `/feeders/{feederId}/schedules`.
/// - Listens to `/feeders/{feederId}/logs` for completed closed-loop dispensing records.
class FirebaseHardwareAdapter implements FeederHardwareAdapter {
  final String feederId;

  final _telemetryController = StreamController<FeederTelemetry>.broadcast();
  final _connectionController = StreamController<FeederConnection>.broadcast();
  final _logController = StreamController<FeedingLog>.broadcast();

  DatabaseReference? _rootRef;
  StreamSubscription<DatabaseEvent>? _telemetrySub;
  StreamSubscription<DatabaseEvent>? _logSub;
  StreamSubscription<DatabaseEvent>? _connectionSub;

  FeederConnection _currentConnection = FeederConnection.connecting;
  bool _isDispensing = false;

  FirebaseHardwareAdapter({this.feederId = 'feeder_01'});

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

    try {
      // Ensure Firebase default app is initialized if available
      if (Firebase.apps.isEmpty) {
        _connectionController.add(FeederConnection.offline);
        return;
      }

      final db = FirebaseDatabase.instance;
      _rootRef = db.ref('feeders/$feederId');

      // Monitor .info/connected
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
      _logSub = _rootRef!.child('logs').limitToLast(5).onChildAdded.listen((event) {
        final val = event.snapshot.value;
        if (val is Map) {
          final logId = event.snapshot.key ?? 'log_${DateTime.now().millisecondsSinceEpoch}';
          final log = FeedingLog.fromMap(logId, val);
          _logController.add(log);
        }
      });
    } catch (e) {
      debugPrint('FirebaseHardwareAdapter initialization fallback: $e');
      _currentConnection = FeederConnection.offline;
      _connectionController.add(_currentConnection);
    }
  }

  @override
  Future<bool> refreshTelemetry() async {
    if (_rootRef == null) return false;
    try {
      final snap = await _rootRef!.child('telemetry').get();
      if (snap.exists && snap.value is Map) {
        _telemetryController.add(FeederTelemetry.fromMap(snap.value as Map));
        return true;
      }
    } catch (e) {
      debugPrint('refreshTelemetry error: $e');
    }
    return false;
  }

  @override
  Future<bool> triggerManualDispense(double targetGrams) async {
    if (_isDispensing || _rootRef == null) return false;
    final cmd = FeederCommand(
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.dispense,
      targetGrams: targetGrams,
      timestamp: DateTime.now(),
      status: CommandStatus.pending,
    );
    try {
      await _rootRef!.child('commands/latest').set(cmd.toJson());
      return true;
    } catch (e) {
      debugPrint('triggerManualDispense error: $e');
      return false;
    }
  }

  @override
  Future<void> cancelDispense() async {
    if (_rootRef == null) return;
    final cmd = FeederCommand(
      id: 'cmd_${DateTime.now().millisecondsSinceEpoch}',
      action: FeederAction.emergencyStop,
      timestamp: DateTime.now(),
      status: CommandStatus.pending,
    );
    try {
      await _rootRef!.child('commands/latest').set(cmd.toJson());
    } catch (e) {
      debugPrint('cancelDispense error: $e');
    }
  }

  @override
  Future<bool> syncSchedules(List<FeedingSchedule> schedules) async {
    if (_rootRef == null) return false;
    try {
      final map = {
        for (final s in schedules) s.id: s.toMap(),
      };
      await _rootRef!.child('schedules').set(map);
      return true;
    } catch (e) {
      debugPrint('syncSchedules error: $e');
      return false;
    }
  }

  @override
  Future<FeederCommand> sendCommand(FeederCommand command) async {
    if (_rootRef == null) {
      return command.copyWith(
        status: CommandStatus.failed,
        errorMessage: 'Firebase database is not connected',
      );
    }
    try {
      await _rootRef!.child('commands/${command.id}').set(command.toJson());
      return command.copyWith(status: CommandStatus.pending);
    } catch (e) {
      return command.copyWith(
        status: CommandStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _logSub?.cancel();
    _connectionSub?.cancel();
    _telemetryController.close();
    _connectionController.close();
    _logController.close();
  }
}
