import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/main.dart';
import 'package:smart_ble_alarm/core/notifications/notification_service.dart';
import 'package:smart_ble_alarm/data/repositories/simulated_ble_repository_impl.dart';
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
}
