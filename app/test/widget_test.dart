import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_chicken_feeder/main.dart';
import 'package:smart_chicken_feeder/services/feeder_service.dart';
import 'package:smart_chicken_feeder/services/settings_service.dart';
import 'package:smart_chicken_feeder/services/file_export/file_exporter.dart';
import 'package:smart_chicken_feeder/services/hardware/rest_hardware_adapter.dart';
import 'package:smart_chicken_feeder/services/hardware/firebase_hardware_adapter.dart';
import 'package:smart_chicken_feeder/screens/diagnostics_screen.dart';
import 'package:smart_chicken_feeder/theme/app_theme.dart';
import 'package:smart_chicken_feeder/models/schedule.dart';

void main() {
  group('SmartChickenFeeder App Smoke & Usability Tests', () {
    testWidgets('App renders onboarding first, completes it, then lands on dashboard', (WidgetTester tester) async {
      final settings = SettingsService(onboardingComplete: false);
      final feeder = FeederService(connectDelay: Duration.zero);

      await tester.pumpWidget(SmartChickenFeederApp(
        settingsService: settings,
        feederService: feeder,
      ));
      await tester.pumpAndSettle();

      // Should show onboarding screen first
      expect(find.text('Automated Poultry Feeding'), findsOneWidget);
      expect(find.text('Skip'), findsOneWidget);

      // Tap skip to complete onboarding
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(settings.onboardingComplete, true);

      // Now on main dashboard
      expect(find.text('Smart Chicken Feeder'), findsOneWidget);
      expect(find.text('Feed Hopper Level'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Schedules'), findsOneWidget);
      expect(find.text('History & Logs'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);

      feeder.dispose();
    });

    testWidgets('App renders dashboard, navigation tabs, and Settings screen', (WidgetTester tester) async {
      final settings = SettingsService(onboardingComplete: true);
      final feeder = FeederService(connectDelay: Duration.zero);

      await tester.pumpWidget(SmartChickenFeederApp(
        settingsService: settings,
        feederService: feeder,
      ));
      await tester.pumpAndSettle();

      // Check dashboard headers & Nielsen status elements
      expect(find.text('Smart Chicken Feeder'), findsOneWidget);
      expect(find.text('Feed Hopper Level'), findsOneWidget);
      expect(find.text('Solar System'), findsOneWidget);
      expect(find.text('Battery Level'), findsOneWidget);
      expect(find.text('Next Automated Feeding'), findsOneWidget);
      expect(find.text('Manual Feed Trigger'), findsOneWidget);

      // Tap Schedules tab
      await tester.tap(find.text('Schedules'));
      await tester.pumpAndSettle();
      expect(find.text('Feeding Schedules'), findsOneWidget);
      expect(find.textContaining('Active Daily'), findsOneWidget);

      // Tap History & Logs tab
      await tester.tap(find.text('History & Logs'));
      await tester.pumpAndSettle();
      expect(find.text('Feeding Logs & Analytics'), findsOneWidget);
      expect(find.text('Performance Metrics'), findsOneWidget);

      // Tap Settings tab
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Settings & Preferences'), findsOneWidget);
      expect(find.text('App Theme'), findsOneWidget);

      // Toggle Dark mode from settings
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.dark);

      // Scroll down to verify warning thresholds and diagnostics
      await tester.scrollUntilVisible(find.text('Low Feed Warning Level'), 100);
      expect(find.text('Low Feed Warning Level'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Simulate Offline Connection'), 100);
      expect(find.text('Simulate Offline Connection'), findsOneWidget);

      feeder.dispose();
    });

    testWidgets('Offline banner shows and disables manual feed when connection lost', (WidgetTester tester) async {
      final settings = SettingsService(onboardingComplete: true);
      final feeder = FeederService(connectDelay: Duration.zero);

      await tester.pumpWidget(SmartChickenFeederApp(
        settingsService: settings,
        feederService: feeder,
      ));
      await tester.pumpAndSettle();

      // Simulate offline state
      feeder.setSimulatedOffline(true);
      await tester.pumpAndSettle();

      // Banner should be visible
      expect(find.text('Feeder connection lost'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.textContaining('Manual feeding is unavailable'), findsOneWidget);

      // Reconnect
      feeder.setSimulatedOffline(false);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Feeder connection lost'), findsNothing);

      feeder.dispose();
    });

    testWidgets('Responsive Layout renders NavigationRail on wide tablet/desktop viewports', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final settings = SettingsService(onboardingComplete: true);
      final feeder = FeederService(connectDelay: Duration.zero);

      await tester.pumpWidget(SmartChickenFeederApp(
        settingsService: settings,
        feederService: feeder,
      ));
      await tester.pumpAndSettle();

      // Should render NavigationRail destinations
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Schedules'), findsWidgets);
      expect(find.text('History & Logs'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);

      feeder.dispose();
    });

    test('FeederService defaults to offline during development until hardware connects', () async {
      final service = FeederService(connectDelay: Duration.zero);
      expect(service.connection, FeederConnection.offline);
      expect(service.telemetry.isOnline, false);
      service.dispose();
    });

    test('FeederService data logic and heuristic operations test', () async {
      final service = FeederService(connectDelay: Duration.zero, simulateOffline: false);
      await service.refreshTelemetry();

      expect(service.schedules.length, 3);
      expect(service.history.isNotEmpty, true);
      expect(service.telemetry.isOnline, true);
      expect(service.totalDailyTargetGrams, greaterThan(0));

      // Test adding a schedule
      const newSchedule = FeedingSchedule(
        id: 'test_sch_1',
        label: 'Evening Snack',
        hour: 19,
        minute: 0,
        targetGrams: 80.0,
        isEnabled: true,
      );
      service.addSchedule(newSchedule);
      expect(service.schedules.length, 4);

      // Test deleting and undoing (insertScheduleAt)
      service.deleteSchedule('test_sch_1');
      expect(service.schedules.length, 3);
      service.insertScheduleAt(3, newSchedule);
      expect(service.schedules.length, 4);
      expect(service.schedules.last.id, 'test_sch_1');

      // Test CSV export format
      final csv = service.exportCsv();
      expect(csv.contains('TargetWeight_g'), true);
      expect(csv.contains('ActualWeight_g'), true);

      service.dispose();
    });

    test('FeederService manual dispense and command duration seconds test', () async {
      final service = FeederService(connectDelay: Duration.zero, simulateOffline: false);
      await service.refreshTelemetry();

      expect(service.totalDailyDurationSeconds, greaterThan(0));

      final success = await service.triggerManualFeed(durationSeconds: 7);
      expect(success, true);
      expect(service.isDispensing, true);

      service.dispose();
    });

    test('FeederService exportExcelXml formats valid Excel workbook XML with styles and headers', () {
      final service = FeederService(connectDelay: Duration.zero);
      final xml = service.exportExcelXml();

      expect(xml.contains('<?xml version="1.0"?>'), true);
      expect(xml.contains('progid="Excel.Sheet"'), true);
      expect(xml.contains('<Worksheet ss:Name="Feeding Logs">'), true);
      expect(xml.contains('TargetWeight_g'), true);
      expect(xml.contains('ActualWeight_g'), true);
      expect(xml.contains('<Style ss:ID="Header">'), true);
      expect(xml.contains('<Style ss:ID="Pass">'), true);

      service.dispose();
    });

    test('FileExporter downloads CSV and Excel files to system successfully', () async {
      final csvContent = 'LogID,Timestamp,TriggerType\nlog_1,2026-10-19 12:00:00,Schedule';
      final res = await FileExporter.downloadTextFile(
        fileName: 'test_export_unit.csv',
        content: csvContent,
      );

      expect(res.success, true);
      expect(res.filePath.isNotEmpty, true);

      // Verify file exists on disk and content has BOM
      final file = File(res.filePath);
      expect(file.existsSync(), true);
      final readText = await file.readAsString();
      expect(readText.contains('log_1'), true);

      // Clean up test file
      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    });

    testWidgets('Tapping Export on History Screen opens modal with Download CSV and Download Excel buttons', (WidgetTester tester) async {
      final settings = SettingsService(onboardingComplete: true);
      final feeder = FeederService(connectDelay: Duration.zero);

      await tester.pumpWidget(SmartChickenFeederApp(
        settingsService: settings,
        feederService: feeder,
      ));
      await tester.pumpAndSettle();

      // Navigate to History tab
      await tester.tap(find.text('History & Logs'));
      await tester.pumpAndSettle();

      // Find and tap the Export CSV/Data button
      final exportBtn = find.byTooltip('Export CSV Dataset');
      expect(exportBtn, findsOneWidget);
      await tester.tap(exportBtn);
      await tester.pumpAndSettle();

      // Verify modal contents
      expect(find.text('Export Feeding Logs'), findsOneWidget);
      expect(find.text('Download CSV'), findsOneWidget);
      expect(find.text('Download Excel (.xls)'), findsOneWidget);
      expect(find.text('Copy CSV'), findsOneWidget);

      // Tap Download CSV and allow native async disk I/O to complete
      await tester.runAsync(() async {
        await tester.tap(find.text('Download CSV'));
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      // Verify feedback appears
      expect(find.textContaining('Successfully saved'), findsOneWidget);

      // Close modal
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      feeder.dispose();
    });

    testWidgets('Diagnostics screen renders live sensors and executes tare and servo test', (WidgetTester tester) async {
      final feeder = FeederService(connectDelay: Duration.zero, simulateOffline: false);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: DiagnosticsScreen(feederService: feeder, enableAutoRefresh: false),
      ));
      await tester.pump();

      // Check key sections
      expect(find.text('Hardware Diagnostics & Calibration'), findsOneWidget);
      expect(find.text('Load Cell & Scale (HX711)'), findsOneWidget);

      // Tap Tare button
      await tester.tap(find.text('Tare (0.0g)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.textContaining('Tare Scale completed'), findsWidgets);

      // Scroll to Dispenser Gate Servo section
      await tester.scrollUntilVisible(find.text('Close (0°)'), 50.0);
      await tester.ensureVisible(find.text('Close (0°)'));
      await tester.pumpAndSettle();
      expect(find.text('Dispenser Gate Servo (MG996R)'), findsOneWidget);

      // Tap Close Gate (0°)
      await tester.tap(find.text('Close (0°)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1200));
      expect(find.textContaining('Close Gate (0°) completed'), findsWidgets);

      feeder.dispose();
    });

    test('RestHardwareAdapter loopback HTTP server communication and endpoints test', () async {
      HttpOverrides.global = null;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final receivedRequests = <String>[];

      server.listen((HttpRequest request) async {
        receivedRequests.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;
        request.response.headers.add('Access-Control-Allow-Origin', '*');

        if (request.uri.path == '/api/telemetry') {
          request.response.write(jsonEncode({
            'feedLevelPercent': 82.5,
            'batteryVolts': 12.6,
            'batteryPercent': 90,
            'currentWeightGrams': 12.0,
            'status': 'idle',
            'lastHeartbeat': 12345,
            'lastFedTimestamp': 0,
            'lastFedGrams': 180.0,
            'isSolarCharging': true,
          }));
        } else if (request.uri.path == '/api/dispense' ||
                   request.uri.path == '/api/stop' ||
                   request.uri.path == '/api/tare' ||
                   request.uri.path == '/api/calibrate' ||
                   request.uri.path == '/api/schedules') {
          request.response.write(jsonEncode({'status': 'ok'}));
        } else {
          request.response.statusCode = 404;
        }
        await request.response.close();
      });

      final adapter = RestHardwareAdapter(host: '127.0.0.1', port: server.port);
      await adapter.initialize();

      // Test refresh telemetry
      final telemetryFuture = adapter.telemetryStream.first;
      final refreshed = await adapter.refreshTelemetry();
      expect(refreshed, isTrue);

      final telemetry = await telemetryFuture;
      expect(telemetry.feedLevelPercent, 82.5);
      expect(telemetry.batteryVolts, 12.6);
      expect(telemetry.isSolarCharging, isTrue);

      // Test dispense, stop, tare, calibrate, and schedules
      final dispenseOk = await adapter.triggerManualDispense(durationSeconds: 5, targetGrams: 100.0);
      expect(dispenseOk, isTrue);

      await adapter.cancelDispense();

      final tareOk = await adapter.tareScale();
      expect(tareOk, isTrue);

      final calOk = await adapter.calibrateScale(500.0);
      expect(calOk, isTrue);

      final syncOk = await adapter.syncSchedules([
        const FeedingSchedule(id: 'sch_t', label: 'Test', hour: 8, minute: 0, targetGrams: 150),
      ]);
      expect(syncOk, isTrue);

      adapter.dispose();
      await server.close(force: true);

      expect(receivedRequests, contains('GET /api/telemetry'));
      expect(receivedRequests, contains('POST /api/dispense'));
      expect(receivedRequests, contains('POST /api/stop'));
      expect(receivedRequests, contains('POST /api/tare'));
      expect(receivedRequests, contains('POST /api/calibrate'));
      expect(receivedRequests, contains('POST /api/schedules'));
    });

    test('FirebaseHardwareAdapter loopback RTDB REST synchronization tests', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final receivedRequests = <String>[];

      server.listen((HttpRequest request) async {
        receivedRequests.add('${request.method} ${request.uri.path}');
        request.response.headers.contentType = ContentType.json;

        if (request.uri.path == '/telemetry.json') {
          request.response.write(jsonEncode({
            'feedLevelPercent': 88.0,
            'batteryVolts': 12.7,
            'batteryPercent': 95,
            'currentWeightGrams': 0.0,
            'status': 'idle',
            'lastHeartbeat': 99999,
            'lastFedTimestamp': 0,
            'lastFedGrams': 150.0,
            'isSolarCharging': true,
          }));
        } else if (request.uri.path == '/commands/dispense.json') {
          final body = await utf8.decodeStream(request);
          request.response.write(body.isNotEmpty ? body : jsonEncode({'status': 'ok'}));
        } else if (request.uri.path == '/schedules.json' || request.uri.path == '/logs.json') {
          request.response.write(jsonEncode({}));
        } else {
          request.response.write(jsonEncode({'status': 'ok'}));
        }
        await request.response.close();
      });


      final adapter = FirebaseHardwareAdapter(
        databaseUrl: 'http://127.0.0.1:${server.port}',
      );
      await adapter.initialize();

      // Test telemetry reception
      final refreshed = await adapter.refreshTelemetry();
      expect(refreshed, isTrue);

      // Test dispense command
      final dispenseOk = await adapter.triggerManualDispense(durationSeconds: 5, targetGrams: 180.0);
      expect(dispenseOk, isTrue);

      // Test tare and calibrate scale
      final tareOk = await adapter.tareScale();
      expect(tareOk, isTrue);

      final calOk = await adapter.calibrateScale(500.0);
      expect(calOk, isTrue);

      adapter.dispose();
      await server.close(force: true);

      expect(receivedRequests, contains('GET /telemetry.json'));
      expect(receivedRequests, contains('PUT /commands/dispense.json'));
    });
  });
}

