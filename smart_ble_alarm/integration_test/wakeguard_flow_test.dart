import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/app/smart_alarm_app.dart';
import 'package:smart_ble_alarm/core/notifications/notification_service.dart';
import 'package:smart_ble_alarm/data/repositories/simulated_ble_repository_impl.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/features/alarms/data/alarm_cloud_sync_service.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/screens/setup_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding can be skipped into setup', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      SmartAlarmApp(
        prefs: prefs,
        bleRepository: SimulatedBleRepositoryImpl(),
        notificationService: NotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Built for mornings that normal alarms do not solve.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Skip for now'));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(prefs.getBool('hasSeenOnboarding'), isTrue);
    expect(find.byType(SetupScreen), findsOneWidget);
  });

  testWidgets('alarm creation persists and requests cloud backup', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final backup = _FakeAlarmCloudSyncService();
    final bloc = AlarmBloc(
      bleRepository: SimulatedBleRepositoryImpl(),
      prefs: prefs,
      alarmCloudSyncService: backup,
    )..add(LoadAlarmsEvent());
    await bloc.stream.firstWhere((state) => !state.isLoading);

    const alarm = Alarm(
      id: 1,
      hour: 7,
      minute: 15,
      dayMask: 0x80,
      qrRequired: true,
      label: 'Morning',
    );

    bloc.add(const AddOrUpdateAlarmEvent(alarm, null, rotateSecureKey: true));
    await bloc.stream.firstWhere((state) => state.alarms.length == 1);

    expect(bloc.state.alarms.single.label, 'Morning');
    expect(AlarmBloc.parseStoredAlarms(prefs.getString('saved_alarms')), [
      alarm,
    ]);
    expect(backup.syncedAlarms.single.id, 1);

    await bloc.close();
  });

  testWidgets('alarm sync succeeds against simulated clock', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = SimulatedBleRepositoryImpl();
    final device = BluetoothDevice.fromId('simulated_device');
    await repo.connectToDevice(device);
    final bloc = AlarmBloc(
      bleRepository: repo,
      prefs: prefs,
      alarmCloudSyncService: _FakeAlarmCloudSyncService(),
    );

    const alarm = Alarm(
      id: 2,
      hour: 6,
      minute: 30,
      dayMask: 0x80 | 0x02,
      qrRequired: false,
    );
    bloc.add(const AddOrUpdateAlarmEvent(alarm, null));
    await bloc.stream.firstWhere((state) => state.alarms.length == 1);

    final completer = Completer<void>();
    bloc.add(SyncAlarmsToDeviceEvent(device, completer: completer));
    await completer.future;

    expect(bloc.state.syncStatusFor(alarm), AlarmSyncStatus.synced);

    await bloc.close();
    await repo.dispose();
  });

  testWidgets('one-time alarm disables after dismissal', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final bloc = AlarmBloc(
      bleRepository: SimulatedBleRepositoryImpl(),
      prefs: prefs,
      alarmCloudSyncService: _FakeAlarmCloudSyncService(),
    );

    const alarm = Alarm(
      id: 3,
      hour: 8,
      minute: 0,
      dayMask: 0x80,
      qrRequired: true,
    );
    bloc.add(const AddOrUpdateAlarmEvent(alarm, null));
    await bloc.stream.firstWhere((state) => state.alarms.length == 1);

    bloc.add(const SetRingingAlarmEvent(3));
    await bloc.stream.firstWhere((state) => state.ringingAlarmId == 3);
    bloc.add(const SetRingingAlarmEvent(null));
    await bloc.stream.firstWhere(
      (state) => state.ringingAlarmId == null && !state.alarms.single.isActive,
    );

    expect(bloc.state.alarms.single.isActive, isFalse);

    await bloc.close();
  });
}

class _FakeAlarmCloudSyncService extends AlarmCloudSyncService {
  List<Alarm> syncedAlarms = const [];

  @override
  Future<List<Alarm>> restoreIfLocalEmpty(List<Alarm> localAlarms) async {
    return localAlarms;
  }

  @override
  Future<void> syncAlarms(List<Alarm> alarms) async {
    syncedAlarms = List<Alarm>.unmodifiable(alarms);
  }
}
