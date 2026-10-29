import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_chicken_feeder/main.dart';
import 'package:smart_chicken_feeder/models/feeder_command.dart';
import 'package:smart_chicken_feeder/models/feeding_log.dart';
import 'package:smart_chicken_feeder/models/schedule.dart';
import 'package:smart_chicken_feeder/models/telemetry.dart';
import 'package:smart_chicken_feeder/screens/diagnostics_screen.dart';
import 'package:smart_chicken_feeder/services/alert_notification_service.dart';
import 'package:smart_chicken_feeder/services/feeder_service.dart';
import 'package:smart_chicken_feeder/services/hardware/firebase_hardware_adapter.dart';
import 'package:smart_chicken_feeder/services/hardware/hardware_adapter.dart';
import 'package:smart_chicken_feeder/services/hardware/mock_hardware_adapter.dart';
import 'package:smart_chicken_feeder/services/settings_service.dart';
import 'package:smart_chicken_feeder/theme/app_theme.dart';

/// In-memory Firebase Realtime Database loopback server for end-to-end integration verification.
class _MockFirebaseRtdbServer {
  late final HttpServer _server;
  String? requiredAuthToken;
  bool simulateServerError = false;

  Map<String, dynamic> telemetry = {
    'feedLevelPercent': 84.0,
    'batteryVolts': 12.65,
    'batteryPercent': 91,
    'currentWeightGrams': 0.0,
    'status': 'idle',
    'lastHeartbeat': DateTime.now().millisecondsSinceEpoch,
    'lastFedTimestamp': DateTime.now().subtract(const Duration(hours: 2)).millisecondsSinceEpoch,
    'lastFedGrams': 160.0,
    'isSolarCharging': true,
  };

  Map<String, dynamic> schedules = {};
  Map<String, dynamic> logs = {};
  Map<String, dynamic>? dispenseCommand;
  Map<String, dynamic>? stopCommand;
  Map<String, dynamic>? latestCommand;

  final List<String> requestLog = [];
  int dispensePutCount = 0;

  int get port => _server.port;
  String get baseUrl => 'http://127.0.0.1:$port';

  Future<void> start() async {
    HttpOverrides.global = null;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handleRequest);
  }

  Future<void> _handleRequest(HttpRequest req) async {
    try {
      final path = req.uri.path;
      final authParam = req.uri.queryParameters['auth'];
      requestLog.add('${req.method} $path${authParam != null ? '?auth=$authParam' : ''}');

      req.response.headers.contentType = ContentType.json;

      if (simulateServerError) {
        req.response.statusCode = 503;
        req.response.write(jsonEncode({'error': 'Service unavailable'}));
        await req.response.close();
        return;
      }

      if (requiredAuthToken != null && authParam != requiredAuthToken) {
        req.response.statusCode = 401;
        req.response.write(jsonEncode({'error': 'Permission denied'}));
        await req.response.close();
        return;
      }

      final bodyText = await utf8.decodeStream(req);
      final dynamic decodedBody = bodyText.isNotEmpty ? jsonDecode(bodyText) : null;

      if (path == '/telemetry.json') {
        if (req.method == 'GET') {
          req.response.write(jsonEncode(telemetry));
        } else if (req.method == 'PUT' && decodedBody is Map) {
          telemetry = Map<String, dynamic>.from(decodedBody);
          req.response.write(jsonEncode(telemetry));
        }
      } else if (path == '/schedules.json') {
        if (req.method == 'GET') {
          req.response.write(schedules.isEmpty ? 'null' : jsonEncode(schedules));
        } else if (req.method == 'PUT' && decodedBody is Map) {
          schedules = Map<String, dynamic>.from(decodedBody);
          req.response.write(jsonEncode(schedules));
        } else if (req.method == 'DELETE') {
          schedules = {};
          req.response.write('null');
        }
      } else if (path == '/logs.json') {
        if (req.method == 'GET') {
          req.response.write(logs.isEmpty ? 'null' : jsonEncode(logs));
        }
      } else if (path.startsWith('/logs/') && path.endsWith('.json')) {
        final id = path.substring('/logs/'.length, path.length - '.json'.length);
        if (req.method == 'PUT' && decodedBody is Map) {
          logs[id] = Map<String, dynamic>.from(decodedBody);
          req.response.write(jsonEncode(logs[id]));
        }
      } else if (path == '/commands/dispense.json') {
        if (req.method == 'GET') {
          req.response.write(dispenseCommand == null ? 'null' : jsonEncode(dispenseCommand));
        } else if (req.method == 'PUT' && decodedBody is Map) {
          dispenseCommand = Map<String, dynamic>.from(decodedBody);
          if (dispenseCommand!['action'] == 'DISPENSE') {
            dispensePutCount++;
          }
          req.response.write(jsonEncode(dispenseCommand));
        } else if (req.method == 'DELETE') {
          dispenseCommand = null;
          req.response.write('null');
        }
      } else if (path == '/commands/stop.json') {
        if (req.method == 'PUT' && decodedBody is Map) {
          stopCommand = Map<String, dynamic>.from(decodedBody);
          req.response.write(jsonEncode(stopCommand));
        } else if (req.method == 'DELETE') {
          stopCommand = null;
          req.response.write('null');
        } else {
          req.response.write(stopCommand == null ? 'null' : jsonEncode(stopCommand));
        }
      } else if (path == '/commands/latest.json') {
        if (req.method == 'GET') {
          req.response.write(latestCommand == null ? 'null' : jsonEncode(latestCommand));
        } else if (req.method == 'PUT' && decodedBody is Map) {
          latestCommand = Map<String, dynamic>.from(decodedBody);
          req.response.write(jsonEncode(latestCommand));
        }
      } else {
        req.response.statusCode = 404;
        req.response.write(jsonEncode({'error': 'Not found'}));
      }

      await req.response.close();
    } catch (_) {}
  }

  Future<void> close() async {
    await _server.close(force: true);
  }
}

void main() {
  group('Pre-Defense End-to-End Integration Audit Suite (Tests A–G)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Test A: Firebase auth token propagation, RTDB roundtrip, and HTTP 401 permission-denied handling', () async {
      final rtdb = _MockFirebaseRtdbServer()..requiredAuthToken = 'secure_esp32_token_123';
      await rtdb.start();

      // 1. Unauthenticated adapter must fail cleanly and NOT report false success
      final unauthAdapter = FirebaseHardwareAdapter(databaseUrl: rtdb.baseUrl);
      final unauthService = FeederService(
        adapter: unauthAdapter,
        enableOsNotifications: false,
      );

      final unauthOk = await unauthService.refreshTelemetry();
      expect(unauthOk, isFalse);
      expect(unauthService.connection, FeederConnection.offline);
      expect(unauthService.lastErrorMessage, contains('permission denied'));

      final unauthFeedOk = await unauthService.triggerManualFeed(durationSeconds: 5);
      expect(unauthFeedOk, isFalse);
      expect(rtdb.dispenseCommand, isNull);
      unauthService.dispose();

      // 2. Authenticated adapter succeeds across telemetry, schedules, and logs
      final authAdapter = FirebaseHardwareAdapter(
        databaseUrl: rtdb.baseUrl,
        authTokenProvider: () async => 'secure_esp32_token_123',
      );
      final authService = FeederService(
        adapter: authAdapter,
        enableOsNotifications: false,
      );

      final telemetryOk = await authService.refreshTelemetry();
      expect(telemetryOk, isTrue);
      expect(authService.isDeviceOnline, isTrue);
      expect(authService.telemetry.feedLevelPercent, 84.0);
      expect(rtdb.requestLog.any((r) => r.contains('GET /telemetry.json?auth=secure_esp32_token_123')), isTrue);

      final testLog = FeedingLog(
        id: 'log_auth_1',
        timestamp: DateTime.now(),
        targetGrams: 100.0,
        actualGrams: 100.5,
        durationSeconds: 5,
        triggerType: 'Manual',
        isSuccess: true,
        batteryVolts: 12.6,
        feedLevelPercent: 83.0,
      );
      expect(await authAdapter.saveFeedingLog(testLog), isTrue);
      expect(rtdb.logs.containsKey('log_auth_1'), isTrue);

      authService.dispose();
      await Future.delayed(const Duration(milliseconds: 50));
      await rtdb.close();
    });

    test('Test B: Schedule creation, Firebase persistence, restart recovery, and single-execution guarantee', () async {
      final rtdb = _MockFirebaseRtdbServer();
      await rtdb.start();

      // Session 1: Create, edit, and delete schedules -> verify persisted to Firebase RTDB
      final service1 = FeederService(
        adapter: FirebaseHardwareAdapter(databaseUrl: rtdb.baseUrl),
        enableOsNotifications: false,
      );
      await service1.loadLocalData();
      await service1.refreshTelemetry();

      // Clear defaults and add two thesis defense schedules
      for (final id in service1.schedules.map((s) => s.id).toList()) {
        service1.deleteSchedule(id);
      }
      await Future.delayed(const Duration(milliseconds: 80));

      const schMorning = FeedingSchedule(
        id: 'sch_defense_1',
        label: 'Defense Morning Feed',
        hour: 7,
        minute: 15,
        durationSeconds: 6,
        targetGrams: 120.0,
        isEnabled: true,
      );
      const schNoon = FeedingSchedule(
        id: 'sch_defense_2',
        label: 'Defense Noon Feed',
        hour: 12,
        minute: 30,
        durationSeconds: 8,
        targetGrams: 160.0,
        isEnabled: true,
      );

      service1.addSchedule(schMorning);
      service1.addSchedule(schNoon);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(rtdb.schedules.keys, containsAll(['sch_defense_1', 'sch_defense_2']));

      // Edit first schedule & pause second schedule
      service1.updateSchedule(schMorning.copyWith(targetGrams: 140.0, durationSeconds: 7));
      service1.toggleSchedule('sch_defense_2', false);
      await Future.delayed(const Duration(milliseconds: 100));
      service1.dispose();

      // Session 2: Fresh service simulating cold app restart from Firebase RTDB
      SharedPreferences.setMockInitialValues({});
      final service2 = FeederService(
        adapter: FirebaseHardwareAdapter(databaseUrl: rtdb.baseUrl),
        enableOsNotifications: false,
      );
      await service2.syncWithFirebaseCloud();

      expect(service2.schedules.length, 2);
      final restored1 = service2.schedules.firstWhere((s) => s.id == 'sch_defense_1');
      final restored2 = service2.schedules.firstWhere((s) => s.id == 'sch_defense_2');
      expect(restored1.targetGrams, 140.0);
      expect(restored1.durationSeconds, 7);
      expect(restored2.isEnabled, isFalse);

      // Verify Firebase mode does NOT auto-dispatch schedule from mobile app (controller owns schedule execution)
      expect(rtdb.dispensePutCount, 0);
      service2.dispose();
      await Future.delayed(const Duration(milliseconds: 50));
      await rtdb.close();
    });

    testWidgets(
      'Test C: Offline ESP32 stale-heartbeat command blocking, duplicate tap guard, SERVO_TEST separation, and Emergency Stop',
      (WidgetTester tester) async {
        final rtdb = _MockFirebaseRtdbServer();
        // Simulate live Firebase bug: cloud HTTP 200 is reachable, BUT ESP32 heartbeat is 5 days stale!
        rtdb.telemetry['lastHeartbeat'] =
            DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch;

        late FirebaseHardwareAdapter fbAdapter;
        late FeederService feeder;

        await tester.runAsync(() async {
          await rtdb.start();
          fbAdapter = FirebaseHardwareAdapter(databaseUrl: rtdb.baseUrl);
          feeder = FeederService(
            adapter: fbAdapter,
            enableOsNotifications: false,
          );
          await feeder.refreshTelemetry();

          // Cloud link is online, but physical ESP32 device is OFFLINE!
          expect(feeder.isConnected, isTrue);
          expect(feeder.isDeviceOnline, isFalse);

          // Attempt manual feed, tare, calibrate, and servo test while ESP32 heartbeat is stale:
          // NONE of them may queue a stale command into Firebase!
          expect(await feeder.triggerManualFeed(durationSeconds: 5), isFalse);
          expect(await feeder.tareScale(), isFalse);
          expect(await feeder.calibrateScale(500.0), isFalse);
          expect(await feeder.testServoGate(45), isFalse);
          expect(rtdb.dispenseCommand, isNull);
        });

        // Verify DiagnosticsScreen shows OFFLINE (not HARDWARE READY) and ConnectionBanner warns operator
        await tester.pumpWidget(MaterialApp(
          theme: AppTheme.light(),
          home: DiagnosticsScreen(feederService: feeder, enableAutoRefresh: false),
        ));
        await tester.pumpAndSettle();

        expect(find.text('OFFLINE'), findsOneWidget);
        expect(find.text('HARDWARE READY'), findsNothing);
        expect(find.text('Feeder controller offline'), findsOneWidget);

        // Now bring ESP32 online with a fresh heartbeat and verify command safeguards
        await tester.runAsync(() async {
          rtdb.telemetry['lastHeartbeat'] = DateTime.now().millisecondsSinceEpoch;
          await feeder.refreshTelemetry();
        });
        await tester.pumpAndSettle();

        expect(feeder.isDeviceOnline, isTrue);
        expect(find.text('HARDWARE READY'), findsOneWidget);

        await tester.runAsync(() async {
          // Rapid double-tap test: fire two manual feed calls concurrently -> only 1 command may transmit!
          final results = await Future.wait([
            feeder.triggerManualFeed(durationSeconds: 5, targetGrams: 100.0),
            feeder.triggerManualFeed(durationSeconds: 5, targetGrams: 100.0),
          ]);
          expect(results.where((ok) => ok).length, 1);
          expect(rtdb.dispensePutCount, 1);
          expect(rtdb.dispenseCommand?['action'], 'DISPENSE');
          expect(rtdb.dispenseCommand?['status'], 'pending');

          // Simulate controller lifecycle acknowledgement on /commands/latest.json
          rtdb.latestCommand = {
            'id': rtdb.dispenseCommand!['id'],
            'action': 'DISPENSE',
            'status': 'completed',
            'actualGrams': 100.4,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          };
          final latestAck = await fbAdapter.fetchLatestCommandStatus();
          expect(latestAck, isNotNull);
          expect(latestAck!.status, CommandStatus.completed);
          expect(latestAck.actualGrams, 100.4);

          // Verify testServoGate(0) sends SERVO_TEST with servoAngle=0 (NOT DISPENSE!)
          expect(await feeder.testServoGate(0), isTrue);
          expect(rtdb.dispenseCommand?['action'], 'SERVO_TEST');
          expect(rtdb.dispenseCommand?['servoAngle'], 0);
          expect(rtdb.dispenseCommand?['durationSeconds'], 0);

          // Verify Emergency Stop writes STOP to BOTH /commands/stop.json and /commands/dispense.json
          feeder.cancelDispensing();
          await Future.delayed(const Duration(milliseconds: 100));
          expect(rtdb.stopCommand?['action'], 'STOP');
          expect(rtdb.dispenseCommand?['action'], 'STOP');

          feeder.dispose();
          await Future.delayed(const Duration(milliseconds: 50));
          await rtdb.close();
        });
      },
    );

    test('Test C2: Mid-dispense Emergency Stop aborts motor immediately and records aborted log', () async {
      final mock = MockHardwareAdapter(
        connectDelay: Duration.zero,
        dispenseTickInterval: const Duration(milliseconds: 60),
        simulateOffline: false,
      );
      final service = FeederService(adapter: mock, enableOsNotifications: false);
      await service.refreshTelemetry();

      final dispenseFuture = service.triggerManualFeed(durationSeconds: 10, targetGrams: 200.0);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(service.isDispensing, isTrue);

      // Issue emergency stop mid-cycle
      service.cancelDispensing();
      expect(service.isDispensing, isFalse);

      final completedNormally = await dispenseFuture;
      await Future.delayed(const Duration(milliseconds: 20));

      expect(completedNormally, isFalse);
      expect(service.isDispensing, isFalse);
      expect(mock.lastServoAngle, 0);
      expect(service.history.first.isSuccess, isFalse);
      expect(service.history.first.triggerType, contains('Aborted'));
      expect(service.history.first.actualGrams, lessThan(200.0));

      service.dispose();
    });

    testWidgets(
      'Test D: Out-of-range sensor clamping and explicit ultrasonic fault banner (no false low-feed masking)',
      (WidgetTester tester) async {
        // 1. Out-of-range / NaN clamping verification
        final clamped = FeederTelemetry.fromMap({
          'feedLevelPercent': 195.0,
          'batteryVolts': -3.5,
          'batteryPercent': 240,
          'currentWeightGrams': double.nan,
          'status': 'idle',
          'lastHeartbeat': DateTime.now().millisecondsSinceEpoch,
        });
        expect(clamped.feedLevelPercent, 100.0);
        expect(clamped.batteryVolts, 0.0);
        expect(clamped.batteryPercent, 100);
        expect(clamped.currentWeightGrams, 0.0);

        // 2. Ultrasonic sensor timeout surfaces Hardware / Sensor Error + blocks manual feed
        final mock = MockHardwareAdapter(connectDelay: Duration.zero, simulateOffline: false);
        final settings = SettingsService(onboardingComplete: true);
        final feeder = FeederService(adapter: mock, enableOsNotifications: false);

        await tester.pumpWidget(SmartChickenFeederApp(
          settingsService: settings,
          feederService: feeder,
        ));
        await tester.pumpAndSettle();

        mock.emitTestTelemetry(FeederTelemetry.fromMap({
          'feedLevelPercent': 0.0,
          'batteryVolts': 11.4,
          'batteryPercent': 12,
          'currentWeightGrams': 0.0,
          'status': 'idle',
          'sensorError': 'ultrasonic_timeout',
          'lastHeartbeat': DateTime.now().millisecondsSinceEpoch,
          'isSolarCharging': false,
        }));
        await tester.pumpAndSettle();

        // Both Hardware/Sensor Error AND Low Battery Warning must show simultaneously,
        // and ultrasonic failure must NOT be misreported as a Low Feed Warning!
        expect(find.textContaining('Hardware / Sensor Error (ultrasonic_timeout)'), findsOneWidget);
        expect(find.textContaining('Low Battery Warning'), findsOneWidget);
        expect(find.textContaining('Low Feed Warning'), findsNothing);
        expect(find.textContaining('Dispense blocked: Hardware/sensor fault active'), findsOneWidget);

        // Confirm manual feed is rejected at service layer during active sensor error
        expect(await feeder.triggerManualFeed(durationSeconds: 5), isFalse);

        feeder.dispose();
      },
    );

    test('Test E: Network interruption detection and clean recovery without unintended dispense', () async {
      final rtdb = _MockFirebaseRtdbServer();
      await rtdb.start();

      final feeder = FeederService(
        adapter: FirebaseHardwareAdapter(databaseUrl: rtdb.baseUrl),
        enableOsNotifications: false,
      );
      expect(await feeder.refreshTelemetry(), isTrue);
      expect(feeder.isDeviceOnline, isTrue);

      // Simulate cloud outage (HTTP 503)
      rtdb.simulateServerError = true;
      expect(await feeder.refreshTelemetry(), isFalse);
      expect(feeder.connection, FeederConnection.offline);
      expect(feeder.isDeviceOnline, isFalse);
      expect(await feeder.triggerManualFeed(durationSeconds: 5), isFalse);

      // Restore cloud connectivity
      rtdb.simulateServerError = false;
      rtdb.telemetry['lastHeartbeat'] = DateTime.now().millisecondsSinceEpoch;
      expect(await feeder.retryConnection(), isTrue);
      expect(feeder.connection, FeederConnection.online);
      expect(feeder.isDeviceOnline, isTrue);
      expect(rtdb.dispensePutCount, 0);

      feeder.dispose();
      await Future.delayed(const Duration(milliseconds: 50));
      await rtdb.close();
    });

    test('Test F: AlertNotificationService deduplication, hysteresis recovery, and zero cold-start false alerts', () async {
      final alertSvc = AlertNotificationService(
        cooldown: const Duration(minutes: 15),
        enableOsNotifications: false,
      );
      await alertSvc.initialize();
      addTearDown(alertSvc.dispose);

      // 1. Offline cold-start telemetry (lastHeartbeat == null) must emit ZERO alerts
      final coldAlerts = await alertSvc.evaluateTelemetry(
        FeederTelemetry.initial(),
        lowFeedThreshold: 20.0,
        lowBatteryThreshold: 20.0,
      );
      expect(coldAlerts, isEmpty);

      // 2. Low feed + Low battery on live telemetry -> 2 distinct alerts
      final firstWave = await alertSvc.evaluateTelemetry(
        FeederTelemetry(
          feedLevelPercent: 14.0,
          batteryVolts: 11.4,
          batteryPercent: 15,
          currentWeightGrams: 0.0,
          status: FeederStatus.lowFeed,
          lastHeartbeat: DateTime.now(),
        ),
        lowFeedThreshold: 20.0,
        lowBatteryThreshold: 20.0,
      );
      expect(firstWave.map((a) => a.category), containsAll(['low_feed', 'low_battery']));

      // 3. Repeated polling tick with same low values -> 0 duplicate alerts!
      final duplicateWave = await alertSvc.evaluateTelemetry(
        FeederTelemetry(
          feedLevelPercent: 13.5,
          batteryVolts: 11.4,
          batteryPercent: 15,
          currentWeightGrams: 0.0,
          status: FeederStatus.lowFeed,
          lastHeartbeat: DateTime.now(),
        ),
        lowFeedThreshold: 20.0,
        lowBatteryThreshold: 20.0,
      );
      expect(duplicateWave, isEmpty);

      // 4. Refill hopper above hysteresis (>= 22%) and recharge battery -> clears latch,
      //    so a subsequent drop below 20% alerts promptly again!
      await alertSvc.evaluateTelemetry(
        FeederTelemetry(
          feedLevelPercent: 85.0,
          batteryVolts: 12.7,
          batteryPercent: 92,
          currentWeightGrams: 0.0,
          status: FeederStatus.idle,
          lastHeartbeat: DateTime.now(),
        ),
        lowFeedThreshold: 20.0,
        lowBatteryThreshold: 20.0,
      );

      final retriggered = await alertSvc.evaluateTelemetry(
        FeederTelemetry(
          feedLevelPercent: 16.0,
          batteryVolts: 12.7,
          batteryPercent: 92,
          currentWeightGrams: 0.0,
          status: FeederStatus.lowFeed,
          lastHeartbeat: DateTime.now(),
        ),
        lowFeedThreshold: 20.0,
        lowBatteryThreshold: 20.0,
      );
      expect(retriggered.length, 1);
      expect(retriggered.first.category, 'low_feed');

      // 5. Failed feeding log alerts exactly once; historical logs are ignored
      alertSvc.seedHistoricalLogIds(['log_old_fail']);
      expect(
        await alertSvc.evaluateFeedingLog(FeedingLog(
          id: 'log_old_fail',
          timestamp: DateTime.now(),
          targetGrams: 100,
          actualGrams: 10,
          durationSeconds: 2,
          triggerType: 'Manual',
          isSuccess: false,
          batteryVolts: 12.4,
          feedLevelPercent: 50,
        )),
        isNull,
      );

      final freshFailLog = FeedingLog(
        id: 'log_fresh_jam',
        timestamp: DateTime.now(),
        targetGrams: 120,
        actualGrams: 18.5,
        durationSeconds: 3,
        triggerType: 'Manual (Motor Jam)',
        isSuccess: false,
        batteryVolts: 12.4,
        feedLevelPercent: 50,
      );
      final failAlert = await alertSvc.evaluateFeedingLog(freshFailLog);
      expect(failAlert, isNotNull);
      expect(failAlert!.category, 'dispense_failed');
      expect(await alertSvc.evaluateFeedingLog(freshFailLog), isNull);
    });

    test('Test G: Full restart and recovery preserves settings, schedules, and logs with zero unintended actuation', () async {
      final rtdb = _MockFirebaseRtdbServer();
      await rtdb.start();

      // First boot: configure settings + schedule + log
      final s1 = await SettingsService.load();
      s1.setFeederName('Defense Prototype Unit');
      s1.setLowFeedThreshold(25.0);
      s1.setLowBatteryThreshold(25.0);
      await s1.setHardwareTransport(HardwareTransportType.firebaseCloud);
      await s1.save();

      final f1 = FeederService(
        adapter: FirebaseHardwareAdapter(databaseUrl: rtdb.baseUrl),
        lowFeedThreshold: s1.lowFeedThreshold,
        lowBatteryThreshold: s1.lowBatteryThreshold,
        enableOsNotifications: false,
      );
      await f1.loadLocalData();
      f1.addSchedule(const FeedingSchedule(
        id: 'sch_recovery_test',
        label: 'Recovery Feed',
        hour: 16,
        minute: 0,
        durationSeconds: 5,
        targetGrams: 100.0,
        isEnabled: true,
      ));
      await Future.delayed(const Duration(milliseconds: 100));
      f1.dispose();

      // Second boot: reload everything from persisted storage + cloud RTDB
      final s2 = await SettingsService.load();
      expect(s2.feederName, 'Defense Prototype Unit');
      expect(s2.lowFeedThreshold, 25.0);
      expect(s2.hardwareTransport, HardwareTransportType.firebaseCloud);

      final f2 = FeederService(
        adapter: FirebaseHardwareAdapter(databaseUrl: rtdb.baseUrl),
        lowFeedThreshold: s2.lowFeedThreshold,
        lowBatteryThreshold: s2.lowBatteryThreshold,
        enableOsNotifications: false,
      );
      await f2.loadLocalData();
      await f2.syncWithFirebaseCloud();
      await f2.refreshTelemetry();

      expect(f2.schedules.any((s) => s.id == 'sch_recovery_test'), isTrue);
      expect(rtdb.dispenseCommand, isNull);
      expect(rtdb.dispensePutCount, 0);

      f2.dispose();
      await Future.delayed(const Duration(milliseconds: 50));
      await rtdb.close();
    });
  });
}
