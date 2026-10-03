import 'package:flutter_test/flutter_test.dart';
import 'package:smart_chicken_feeder/main.dart';
import 'package:smart_chicken_feeder/services/feeder_service.dart';
import 'package:smart_chicken_feeder/models/schedule.dart';

void main() {
  group('SmartChickenFeeder App Smoke Tests', () {
    testWidgets('App renders dashboard and navigation bar', (WidgetTester tester) async {
      await tester.pumpWidget(const SmartChickenFeederApp());
      await tester.pumpAndSettle();

      // Check dashboard headers
      expect(find.text('Smart Chicken Feeder'), findsOneWidget);
      expect(find.text('Solar-Powered • Automated Dispenser'), findsOneWidget);
      expect(find.text('Feed Hopper Level'), findsOneWidget);
      expect(find.text('Solar System'), findsOneWidget);
      expect(find.text('Battery Level'), findsOneWidget);

      // Check navigation destinations
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Schedules'), findsOneWidget);
      expect(find.text('History & Logs'), findsOneWidget);

      // Tap Schedules tab
      await tester.tap(find.text('Schedules'));
      await tester.pumpAndSettle();
      expect(find.text('Feeding Schedules'), findsOneWidget);

      // Tap History & Logs tab
      await tester.tap(find.text('History & Logs'));
      await tester.pumpAndSettle();
      expect(find.text('Feeding Logs & Analytics'), findsOneWidget);
      expect(find.text('Performance Metrics'), findsOneWidget);
    });

    test('FeederService data logic test', () async {
      final service = FeederService();

      expect(service.schedules.length, 3);
      expect(service.history.isNotEmpty, true);
      expect(service.telemetry.isOnline, true);

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

      // Test CSV export format
      final csv = service.exportCsv();
      expect(csv.contains('TargetWeight_g'), true);
      expect(csv.contains('ActualWeight_g'), true);

      service.dispose();
    });
  });
}
