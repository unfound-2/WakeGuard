import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/app/smart_alarm_app.dart';
import 'package:smart_ble_alarm/core/notifications/notification_service.dart';
import 'package:smart_ble_alarm/data/repositories/simulated_ble_repository_impl.dart';
import 'package:smart_ble_alarm/app/navigation/main_screen.dart';
import 'package:smart_ble_alarm/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/screens/setup_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      SmartAlarmApp(
        prefs: prefs,
        bleRepository: SimulatedBleRepositoryImpl(),
        notificationService: NotificationService(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('onboarding and setup skip route through app state', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      SmartAlarmApp(
        prefs: prefs,
        bleRepository: SimulatedBleRepositoryImpl(),
        notificationService: NotificationService(),
      ),
    );
    await tester.pump();

    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(prefs.getBool('hasSeenOnboarding'), isTrue);
    expect(find.byType(SetupScreen), findsOneWidget);

    await tester.ensureVisible(find.text('Replay onboarding'));
    await tester.tap(find.text('Replay onboarding'));
    await tester.pump();

    expect(prefs.getBool('hasSeenOnboarding'), isFalse);
    expect(find.byType(OnboardingScreen), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    expect(find.byType(SetupScreen), findsOneWidget);

    await tester.tap(find.text('Continue Without Clock'));
    await tester.pump();

    expect(prefs.getBool('setupSkipped'), isTrue);
    expect(find.byType(MainScreen), findsOneWidget);
  });

  testWidgets('display tab opens and scrolls without layout assertions', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'hasSeenOnboarding': true,
      'setupSkipped': true,
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      SmartAlarmApp(
        prefs: prefs,
        bleRepository: SimulatedBleRepositoryImpl(),
        notificationService: NotificationService(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Display'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Live Preview'), findsOneWidget);

    final pageList = find.byType(ListView).first;
    await tester.drag(pageList, const Offset(0, -900));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.drag(pageList, const Offset(0, 700));
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
  });
}
