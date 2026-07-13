import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/data/datasources/image_recognition_datasource.dart';
import 'package:smart_ble_alarm/data/repositories/simulated_ble_repository_impl.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/features/alarms/data/alarm_cloud_sync_service.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';

void main() {
  group('ImageRecognitionDatasource.matchesLabel', () {
    test('matches case-insensitively and ignores surrounding whitespace', () {
      expect(
        ImageRecognitionDatasource.matchesLabel('Toothbrush', ' toothbrush '),
        isTrue,
      );
    });

    test('matches when either label contains the other', () {
      expect(
        ImageRecognitionDatasource.matchesLabel('Coffee cup', 'cup'),
        isTrue,
      );
      expect(
        ImageRecognitionDatasource.matchesLabel('cup', 'Coffee cup'),
        isTrue,
      );
    });

    test('does not match unrelated labels', () {
      expect(
        ImageRecognitionDatasource.matchesLabel('Plant', 'toothbrush'),
        isFalse,
      );
    });

    test('never matches an empty target or detection', () {
      expect(ImageRecognitionDatasource.matchesLabel('Cup', ''), isFalse);
      expect(ImageRecognitionDatasource.matchesLabel('', 'Cup'), isFalse);
    });
  });

  group('Alarm item-scan serialization', () {
    test('round-trips item fields through JSON', () {
      const alarm = Alarm(
        id: 3,
        hour: 7,
        minute: 30,
        dayMask: 0x80,
        qrRequired: true,
        itemLabel: 'Toothbrush',
        itemDescription: 'in the bathroom',
      );

      final restored = Alarm.fromJson(alarm.toJson());

      expect(restored, alarm);
      expect(restored.usesItemScan, isTrue);
    });

    test('decodes legacy alarms saved before item fields existed', () {
      final restored = Alarm.fromJson({
        'id': 1,
        'hour': 6,
        'minute': 0,
        'dayMask': 0x80,
        'qrRequired': true,
      });

      expect(restored.itemLabel, isNull);
      expect(restored.usesItemScan, isFalse);
      expect(restored.label, isNull);
      expect(restored.snoozeEnabled, isFalse);
      expect(restored.snoozeMaxCount, 0);
    });
  });

  group('Alarm label and snooze serialization', () {
    test('round-trips label and snooze fields through JSON', () {
      const alarm = Alarm(
        id: 4,
        hour: 8,
        minute: 15,
        dayMask: 0x80,
        qrRequired: true,
        label: 'Wake up',
        snoozeEnabled: true,
        snoozeMaxCount: 3,
        snoozeDurationMinutes: 10,
        volumePercent: 65,
        gradualWakeSeconds: 45,
      );

      final restored = Alarm.fromJson(alarm.toJson());

      expect(restored, alarm);
      expect(restored.label, 'Wake up');
      expect(restored.snoozeEnabled, isTrue);
      expect(restored.snoozeMaxCount, 3);
      expect(restored.snoozeDurationMinutes, 10);
      expect(restored.volumePercent, 65);
      expect(restored.gradualWakeSeconds, 45);
    });

    test('omits snooze count from JSON when snooze is disabled', () {
      const alarm = Alarm(
        id: 5,
        hour: 9,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
      );

      final json = alarm.toJson();

      expect(json.containsKey('snoozeEnabled'), isFalse);
      expect(json.containsKey('snoozeMaxCount'), isFalse);
      // Default 5-min length is omitted too, so unchanged alarms stay compact.
      expect(json.containsKey('snoozeDurationMinutes'), isFalse);
      // Default volume (80%) and no-fade are omitted for the same reason.
      expect(json.containsKey('volumePercent'), isFalse);
      expect(json.containsKey('gradualWakeSeconds'), isFalse);
      expect(json.containsKey('label'), isFalse);
    });
  });

  group('Alarm.syncHash', () {
    const base = Alarm(
      id: 1,
      hour: 7,
      minute: 30,
      dayMask: 0x81,
      qrRequired: true,
    );

    test('changes when a wire-relevant field changes', () {
      expect(base.copyWith(hour: 8).syncHash, isNot(base.syncHash));
      expect(base.copyWith(minute: 45).syncHash, isNot(base.syncHash));
      expect(base.copyWith(dayMask: 0x82).syncHash, isNot(base.syncHash));
      expect(base.copyWith(qrRequired: false).syncHash, isNot(base.syncHash));
      // Snooze now travels to the clock in byte[5] of the 0x02 frame, so a
      // snooze change must re-mark the alarm out-of-sync (it re-sends the frame).
      expect(
        base.copyWith(snoozeEnabled: true, snoozeMaxCount: 3).syncHash,
        isNot(base.syncHash),
      );
      // ...and so does the snooze length (byte[6]) while snooze is enabled.
      final enabled = base.copyWith(snoozeEnabled: true, snoozeMaxCount: 3);
      expect(
        enabled.copyWith(snoozeDurationMinutes: 10).syncHash,
        isNot(enabled.syncHash),
      );
      // Ring volume (byte[7]) and gradual-wake fade (byte[8]) travel to the
      // clock too, so changing either must re-mark the alarm out-of-sync.
      expect(base.copyWith(volumePercent: 50).syncHash, isNot(base.syncHash));
      expect(
        base.copyWith(gradualWakeSeconds: 30).syncHash,
        isNot(base.syncHash),
      );
    });

    test('collapses snooze to its wire value (enabled=false ⇒ count 0)', () {
      // Two alarms that differ only in a snoozeMaxCount that can't travel
      // (snooze disabled ⇒ wire count 0) must hash identically, so a hidden
      // count change doesn't spuriously force a re-sync.
      const off1 = Alarm(
        id: 1,
        hour: 7,
        minute: 30,
        dayMask: 0x81,
        qrRequired: true,
        snoozeMaxCount: 2,
      );
      const off2 = Alarm(
        id: 1,
        hour: 7,
        minute: 30,
        dayMask: 0x81,
        qrRequired: true,
        snoozeMaxCount: 9,
      );
      expect(off1.syncHash, off2.syncHash);
    });

    test('ignores purely app-side metadata (label, item target)', () {
      // These never reach the clock, so editing them must not mark the alarm
      // out-of-sync.
      expect(base.copyWith(label: 'Meds').syncHash, base.syncHash);
      expect(base.copyWith(itemLabel: 'Toothbrush').syncHash, base.syncHash);
    });

    test('is independent of the alarm id (the map key)', () {
      expect(base.copyWith(id: 9).syncHash, base.syncHash);
    });
  });

  group('AlarmState.syncStatusFor', () {
    const alarm = Alarm(
      id: 2,
      hour: 6,
      minute: 0,
      dayMask: 0x80,
      qrRequired: false,
    );

    test('pending when the clock has no record of the alarm', () {
      const state = AlarmState(alarms: [alarm]);
      expect(state.syncStatusFor(alarm), AlarmSyncStatus.pending);
    });

    test('synced when the stored fingerprint matches the current settings', () {
      final state = AlarmState(
        alarms: const [alarm],
        syncedHashes: {alarm.id: alarm.syncHash},
      );
      expect(state.syncStatusFor(alarm), AlarmSyncStatus.synced);
      expect(state.syncedAlarmCount, 1);
    });

    test('pending again after a wire-relevant edit invalidates the hash', () {
      final edited = alarm.copyWith(minute: 15);
      final state = AlarmState(
        alarms: [edited],
        syncedHashes: {alarm.id: alarm.syncHash},
      );
      expect(state.syncStatusFor(edited), AlarmSyncStatus.pending);
      expect(state.syncedAlarmCount, 0);
    });

    test('failed takes precedence even if a matching hash exists', () {
      final state = AlarmState(
        alarms: const [alarm],
        syncedHashes: {alarm.id: alarm.syncHash},
        syncFailedIds: const {2},
      );
      expect(state.syncStatusFor(alarm), AlarmSyncStatus.failed);
    });
  });

  group('AlarmBloc alarm-storage schema', () {
    const alarm = Alarm(
      id: 1,
      hour: 7,
      minute: 30,
      dayMask: 0x81,
      qrRequired: true,
      label: 'Wake up',
    );

    test('encodes alarms in a versioned v2 envelope', () {
      final decoded =
          jsonDecode(AlarmBloc.encodeStoredAlarms(const [alarm]))
              as Map<String, dynamic>;
      expect(decoded['version'], 2);
      expect(decoded['alarms'], isA<List<dynamic>>());
    });

    test('round-trips alarms through encode then parse (v2)', () {
      final restored = AlarmBloc.parseStoredAlarms(
        AlarmBloc.encodeStoredAlarms(const [alarm]),
      );
      expect(restored, const [alarm]);
    });

    test('migrates legacy v1 bare-list storage', () {
      final legacy = jsonEncode([alarm.toJson()]);
      expect(AlarmBloc.parseStoredAlarms(legacy), const [alarm]);
    });

    test('returns empty for null, empty-envelope or unrecognised shapes', () {
      expect(AlarmBloc.parseStoredAlarms(null), isEmpty);
      expect(AlarmBloc.parseStoredAlarms(jsonEncode({'version': 2})), isEmpty);
      expect(AlarmBloc.parseStoredAlarms(jsonEncode(42)), isEmpty);
    });

    test('loads local alarms without auto-restoring cloud backups', () async {
      SharedPreferences.setMockInitialValues({
        'saved_alarms': AlarmBloc.encodeStoredAlarms(const []),
      });
      final prefs = await SharedPreferences.getInstance();
      final cloudSync = _RecordingAlarmCloudSyncService(
        restored: const [alarm],
      );
      final repository = SimulatedBleRepositoryImpl();
      final bloc = AlarmBloc(
        bleRepository: repository,
        prefs: prefs,
        alarmCloudSyncService: cloudSync,
      );
      addTearDown(() async {
        await bloc.close();
        repository.dispose();
      });

      bloc.add(LoadAlarmsEvent());

      final loaded = await bloc.stream.firstWhere((state) => !state.isLoading);
      expect(loaded.alarms, isEmpty);
      expect(cloudSync.restoreCalls, 0);
      expect(cloudSync.restoreIfLocalEmptyCalls, 0);
      expect(cloudSync.syncCalls, 0);
    });
  });
}

class _RecordingAlarmCloudSyncService extends AlarmCloudSyncService {
  final List<Alarm> restored;
  int restoreCalls = 0;
  int restoreIfLocalEmptyCalls = 0;
  int syncCalls = 0;

  _RecordingAlarmCloudSyncService({required this.restored});

  @override
  Future<List<Alarm>> restoreIfLocalEmpty(List<Alarm> localAlarms) async {
    restoreIfLocalEmptyCalls++;
    return restored;
  }

  @override
  Future<List<Alarm>> restoreBackups({List<Alarm> fallback = const []}) async {
    restoreCalls++;
    return restored;
  }

  @override
  Future<void> syncAlarms(List<Alarm> alarms) async {
    syncCalls++;
  }
}
