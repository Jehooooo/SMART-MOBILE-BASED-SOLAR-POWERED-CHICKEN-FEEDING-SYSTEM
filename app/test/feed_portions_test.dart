import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_chicken_feeder/main.dart';
import 'package:smart_chicken_feeder/models/feeding_log.dart';
import 'package:smart_chicken_feeder/models/schedule.dart';
import 'package:smart_chicken_feeder/services/feeder_service.dart';
import 'package:smart_chicken_feeder/services/settings_service.dart';
import 'package:smart_chicken_feeder/utils/feed_portions.dart';
import 'mocks/mock_hardware_adapter.dart';

void main() {
  group('FeedPortions client calibration & kg/g formatting', () {
    test('gramsForDuration matches bench points and piecewise interpolation', () {
      expect(FeedPortions.gramsForDuration(0), 0.0);
      expect(FeedPortions.gramsForDuration(1), 600.0);
      expect(FeedPortions.gramsForDuration(2), 700.0);
      expect(FeedPortions.gramsForDuration(3), 800.0);
      expect(FeedPortions.gramsForDuration(5), 1000.0);
      expect(FeedPortions.gramsForDuration(7), 2200.0);
      expect(FeedPortions.gramsForDuration(10), 4000.0);
      expect(FeedPortions.gramsForDuration(15), 8000.0);
      expect(FeedPortions.gramsForDuration(30), 20000.0);
    });

    test('formatWeight formats g below 1000 g and trimmed kg at >= 1000 g', () {
      expect(FeedPortions.formatWeight(0), '0 g');
      expect(FeedPortions.formatWeight(1.8), '1.8 g');
      expect(FeedPortions.formatWeight(-20), '-20 g');
      expect(FeedPortions.formatWeight(600), '600 g');
      expect(FeedPortions.formatWeight(1000), '1 kg');
      expect(FeedPortions.formatWeight(1800), '1.8 kg');
      expect(FeedPortions.formatWeight(1250), '1.25 kg');
      expect(FeedPortions.formatWeight(4000), '4 kg');
      expect(FeedPortions.formatWeight(8000), '8 kg');
      expect(FeedPortions.formatWeight(20000), '20 kg');
    });

    test('formatForDuration formats duration using calibrated portions', () {
      expect(FeedPortions.formatForDuration(1), '600 g');
      expect(FeedPortions.formatForDuration(3), '800 g');
      expect(FeedPortions.formatForDuration(5), '1 kg');
      expect(FeedPortions.formatForDuration(7), '2.2 kg');
      expect(FeedPortions.formatForDuration(10), '4 kg');
      expect(FeedPortions.formatForDuration(15), '8 kg');
      expect(FeedPortions.formatForDuration(30), '20 kg');
    });

    test('displayGramsForLog prefers duration calibration over raw stored target/actual', () {
      final logWithDuration = FeedingLog(
        id: 'log_1s',
        timestamp: DateTime(2026, 11, 22, 20, 48),
        targetGrams: 20.0,
        actualGrams: 0.0,
        durationSeconds: 1,
        triggerType: 'Manual',
      );
      expect(FeedPortions.displayGramsForLog(logWithDuration), 600.0);

      final logZeroDuration = FeedingLog(
        id: 'log_0s',
        timestamp: DateTime(2026, 11, 22, 20, 48),
        targetGrams: 150.0,
        actualGrams: 10.0,
        durationSeconds: 0,
        triggerType: 'Manual',
      );
      expect(FeedPortions.displayGramsForLog(logZeroDuration), 150.0);
    });
  });

  group('Offline Simulation / Test Mode (Frontend Only)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('enabling simulation unlocks offline testing and restores real state on exit without persistence', () async {
      final offlineAdapter = MockHardwareAdapter(connectDelay: Duration.zero, simulateOffline: true);
      final service = FeederService(adapter: offlineAdapter, enableOsNotifications: false);
      await Future<void>.delayed(Duration.zero);

      service.addSchedule(const FeedingSchedule(
        id: 'real_sch_1',
        label: 'Real Morning',
        hour: 7,
        minute: 0,
        durationSeconds: 5,
        targetGrams: 100.0,
      ));
      expect(service.isDeviceOnline, isFalse);
      expect(service.history, isEmpty);

      // Enable Offline Simulation Mode
      service.setOfflineSimulationMode(true);
      expect(service.isOfflineSimulationMode, isTrue);
      expect(service.isDeviceOnline, isTrue);
      expect(service.history.length, 4);

      // Exports reflect calibrated display weights and 0.00% variance
      final csv = service.exportCsv();
      expect(csv.contains('1000.0,1000.0,0.00,0.00%'), isTrue);
      expect(csv.contains('600.0,600.0,0.00,0.00%'), isTrue);
      expect(csv.contains('4000.0,4000.0,0.00,0.00%'), isTrue);
      expect(csv.contains('8000.0,8000.0,0.00,0.00%'), isTrue);

      // Simulated manual dispense works while offline and appends calibrated log
      final started = await service.triggerManualFeed(durationSeconds: 10);
      expect(started, isTrue);
      expect(service.isDispensing, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      expect(service.isDispensing, isFalse);
      expect(service.history.length, 5);
      expect(service.history.first.durationSeconds, 10);
      expect(FeederService.configuredGramsForLog(service.history.first), 4000.0);

      // Schedule edits in simulation stay in memory only
      service.addSchedule(const FeedingSchedule(
        id: 'sim_only_sch',
        label: 'Sim Only',
        hour: 9,
        minute: 0,
        durationSeconds: 15,
        targetGrams: 300.0,
      ));
      expect(service.schedules.any((s) => s.id == 'sim_only_sch'), isTrue);

      // Disable Offline Simulation Mode -> real state restored cleanly
      service.setOfflineSimulationMode(false);
      expect(service.isOfflineSimulationMode, isFalse);
      expect(service.isDeviceOnline, isFalse);
      expect(service.history, isEmpty);
      expect(service.schedules.length, 1);
      expect(service.schedules.first.id, 'real_sch_1');

      service.dispose();
    });

    testWidgets('offline banner Simulate button toggles simulation mode and unlocks calibrated UI',
        (WidgetTester tester) async {
      final settings = SettingsService(onboardingComplete: true);
      final mock = MockHardwareAdapter(connectDelay: Duration.zero, simulateOffline: true);
      final feeder = FeederService(adapter: mock, enableOsNotifications: false);

      await tester.pumpWidget(SmartChickenFeederApp(
        settingsService: settings,
        feederService: feeder,
      ));
      await tester.pumpAndSettle();

      // Offline banner offers 1-tap Simulate button
      expect(find.text('Simulate'), findsOneWidget);
      await tester.tap(find.text('Simulate'));
      await tester.pumpAndSettle();

      expect(feeder.isOfflineSimulationMode, isTrue);
      expect(find.text('Offline Simulation Mode'), findsOneWidget);
      expect(find.text('Simulated'), findsOneWidget);

      // Switch to History & Logs tab and verify calibrated kg/g & Target/Dispensed/Variance UI
      await tester.tap(find.text('History & Logs'));
      await tester.pumpAndSettle();
      expect(find.text('Target'), findsWidgets);
      expect(find.text('Dispensed'), findsWidgets);
      expect(find.text('Variance'), findsWidgets);
      expect(find.text('0 g (0.0%)'), findsWidgets);
      expect(find.text('13.6 kg'), findsOneWidget); // 1kg + 600g + 4kg + 8kg = 13.6 kg

      // Exit simulation from top banner
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      expect(feeder.isOfflineSimulationMode, isFalse);
      expect(find.text('Offline Simulation Mode'), findsNothing);

      feeder.dispose();
    });
  });
}
