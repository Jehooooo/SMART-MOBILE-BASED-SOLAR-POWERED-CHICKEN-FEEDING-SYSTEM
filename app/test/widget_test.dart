import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_chicken_feeder/main.dart';
import 'package:smart_chicken_feeder/services/feeder_service.dart';
import 'package:smart_chicken_feeder/models/schedule.dart';

void main() {
  group('SmartChickenFeeder App Smoke & Usability Tests', () {
    testWidgets('App renders dashboard and mobile navigation bar', (WidgetTester tester) async {
      await tester.pumpWidget(const SmartChickenFeederApp());
      await tester.pumpAndSettle();

      // Check dashboard headers & Nielsen status elements
      expect(find.text('Smart Chicken Feeder'), findsOneWidget);
      expect(find.text('Solar-Powered • Automated Dispenser'), findsOneWidget);
      expect(find.text('Feed Hopper Level'), findsOneWidget);
      expect(find.text('Solar System'), findsOneWidget);
      expect(find.text('Battery Level'), findsOneWidget);
      expect(find.text('Next Automated Feeding'), findsOneWidget);
      expect(find.text('Manual Feed Trigger'), findsOneWidget);

      // Check navigation destinations
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Schedules'), findsOneWidget);
      expect(find.text('History & Logs'), findsOneWidget);

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
      expect(find.text('Filter Logs:'), findsOneWidget);
    });

    testWidgets('Responsive Layout renders NavigationRail on wide tablet/desktop viewports', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const SmartChickenFeederApp());
      await tester.pumpAndSettle();

      // Should render NavigationRail destinations
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Schedules'), findsWidgets);
      expect(find.text('History & Logs'), findsWidgets);
    });

    testWidgets('Hardware Info dialog can be opened and dismissed', (WidgetTester tester) async {
      await tester.pumpWidget(const SmartChickenFeederApp());
      await tester.pumpAndSettle();

      // Tap System & Hardware Info icon
      final infoButton = find.byTooltip('System & Hardware Info');
      expect(infoButton, findsOneWidget);
      await tester.tap(infoButton);
      await tester.pumpAndSettle();

      // Check dialog content
      expect(find.text('System & Hardware Guide'), findsOneWidget);
      expect(find.text('Feed Level Sensor (HC-SR04)'), findsOneWidget);
      expect(find.text('Dispenser & Scale (HX711)'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.text('System & Hardware Guide'), findsNothing);
    });

    test('FeederService data logic and heuristic operations test', () async {
      final service = FeederService();

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

      // Test telemetry refresh
      await service.refreshTelemetry();
      expect(service.telemetry.isOnline, true);

      // Test CSV export format
      final csv = service.exportCsv();
      expect(csv.contains('TargetWeight_g'), true);
      expect(csv.contains('ActualWeight_g'), true);

      service.dispose();
    });
  });
}
