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
  group('FeedPortions time-based range estimation & kg/g formatting', () {
    test('formatRangeForDuration matches exact bench-tested estimation ranges', () {
      expect(FeedPortions.formatRangeForDuration(0), '0 g');
      expect(FeedPortions.formatRangeForDuration(1), '550g - 600g');
      expect(FeedPortions.formatRangeForDuration(2), '1kg - 1.1kg');
      expect(FeedPortions.formatRangeForDuration(3), '1.1kg - 1.3kg');
      expect(FeedPortions.formatRangeForDuration(4), '1.6kg - 1.9kg');
      expect(FeedPortions.formatRangeForDuration(5), '1.6kg - 2.3kg');
      expect(FeedPortions.formatRangeForDuration(10), '3.2kg - 4.6kg');
    });

    test('gramsForDuration returns midpoint of each estimated range', () {
      expect(FeedPortions.gramsForDuration(0), 0.0);
      expect(FeedPortions.gramsForDuration(1), 575.0);
      expect(FeedPortions.gramsForDuration(2), 1050.0);
      expect(FeedPortions.gramsForDuration(3), 1200.0);
      expect(FeedPortions.gramsForDuration(4), 1750.0);
      expect(FeedPortions.gramsForDuration(5), 1950.0);
      expect(FeedPortions.gramsForDuration(10), 3900.0);
    });

    test('formatWeight formats g below 1000 g and trimmed kg at >= 1000 g', () {
      expect(FeedPortions.formatWeight(0), '0 g');
      expect(FeedPortions.formatWeight(1.8), '1.8 g');
      expect(FeedPortions.formatWeight(-20), '-20 g');
      expect(FeedPortions.formatWeight(550.0), '550 g');
      expect(FeedPortions.formatWeight(600.0), '600 g');
      expect(FeedPortions.formatWeight(1000), '1 kg');
      expect(FeedPortions.formatWeight(1100.0), '1.1 kg');
      expect(FeedPortions.formatWeight(1300.0), '1.3 kg');
      expect(FeedPortions.formatWeight(1600.0), '1.6 kg');
      expect(FeedPortions.formatWeight(1900.0), '1.9 kg');
      expect(FeedPortions.formatWeight(2300.0), '2.3 kg');
    });

    test('displayGramsForLog and formatRangeForLog prefer duration estimation over raw values', () {
      final logWithDuration = FeedingLog(
        id: 'log_1s',
        timestamp: DateTime(2026, 11, 22, 20, 48),
        targetGrams: 20.0,
        actualGrams: 0.0,
        durationSeconds: 1,
        triggerType: 'Manual',
      );
      expect(FeedPortions.displayGramsForLog(logWithDuration), 575.0);
      expect(FeedPortions.formatRangeForLog(logWithDuration), '550g - 600g');

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
      expect(service.history.length, 5);
      expect(service.totalDispensedRangeLabel, '5.85kg - 7.2kg');

      // Exports reflect midpoint estimated display weights and 0.00% variance
      final csv = service.exportCsv();
      expect(csv.contains('575.0,575.0,0.00,0.00%'), isTrue);
      expect(csv.contains('1050.0,1050.0,0.00,0.00%'), isTrue);
      expect(csv.contains('1200.0,1200.0,0.00,0.00%'), isTrue);
      expect(csv.contains('1750.0,1750.0,0.00,0.00%'), isTrue);
      expect(csv.contains('1950.0,1950.0,0.00,0.00%'), isTrue);

      // Simulated manual dispense works while offline and appends estimated log
      final started = await service.triggerManualFeed(durationSeconds: 4);
      expect(started, isTrue);
      expect(service.isDispensing, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 2000));
      expect(service.isDispensing, isFalse);
      expect(service.history.length, 6);
      expect(service.history.first.durationSeconds, 4);
      expect(FeederService.configuredGramsForLog(service.history.first), 1750.0);

      // Schedule edits in simulation stay in memory only
      service.addSchedule(const FeedingSchedule(
        id: 'sim_only_sch',
        label: 'Sim Only',
        hour: 9,
        minute: 0,
        durationSeconds: 5,
        targetGrams: 100.0,
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

    testWidgets('offline banner Simulate button toggles simulation mode and shows estimated ranges',
        (WidgetTester tester) async {
      final settings = SettingsService(onboardingComplete: true);
      final mock = MockHardwareAdapter(connectDelay: Duration.zero, simulateOffline: true);
      final feeder = FeederService(adapter: mock, enableOsNotifications: false);

      await tester.pumpWidget(SmartChickenFeederApp(
        settingsService: settings,
        feederService: feeder,
      ));
      await tester.pumpAndSettle();

      // Dashboard shows exact preset range chips
      expect(find.text('1s (550g - 600g)'), findsWidgets);
      expect(find.text('2s (1kg - 1.1kg)'), findsOneWidget);
      expect(find.text('3s (1.1kg - 1.3kg)'), findsOneWidget);
      expect(find.text('4s (1.6kg - 1.9kg)'), findsOneWidget);
      expect(find.text('5s (1.6kg - 2.3kg)'), findsOneWidget);

      // Offline banner offers 1-tap Simulate button
      expect(find.text('Simulate'), findsOneWidget);
      await tester.tap(find.text('Simulate'));
      await tester.pumpAndSettle();

      expect(feeder.isOfflineSimulationMode, isTrue);
      expect(find.text('Offline Simulation Mode'), findsOneWidget);
      expect(find.text('Simulated'), findsOneWidget);

      // Switch to History & Logs tab and verify estimated ranges & 0% variance UI
      await tester.tap(find.text('History & Logs'));
      await tester.pumpAndSettle();
      expect(find.text('Target'), findsWidgets);
      expect(find.text('Dispensed'), findsWidgets);
      expect(find.text('Variance'), findsWidgets);
      expect(find.text('0 g (0.0%)'), findsWidgets);
      expect(find.text('5.85kg - 7.2kg'), findsOneWidget);

      // Exit simulation from top banner
      await tester.tap(find.text('Exit'));
      await tester.pumpAndSettle();
      expect(feeder.isOfflineSimulationMode, isFalse);
      expect(find.text('Offline Simulation Mode'), findsNothing);

      feeder.dispose();
    });
  });
}
