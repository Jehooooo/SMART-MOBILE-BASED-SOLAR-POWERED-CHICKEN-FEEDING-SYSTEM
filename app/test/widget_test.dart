import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_chicken_feeder/main.dart';
import 'package:smart_chicken_feeder/services/feeder_service.dart';
import 'package:smart_chicken_feeder/services/settings_service.dart';
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
      expect(find.text('Low Feed Warning Level'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Simulate Offline Connection'), 100);
      expect(find.text('Simulate Offline Connection'), findsOneWidget);

      // Scroll back up and toggle Dark mode from settings
      await tester.scrollUntilVisible(find.text('Dark'), -100);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(settings.themeMode, ThemeMode.dark);

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

    test('FeederService data logic and heuristic operations test', () async {
      final service = FeederService(connectDelay: Duration.zero);
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
  });
}
