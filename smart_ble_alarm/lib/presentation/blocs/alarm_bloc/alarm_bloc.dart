import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/ble/ble_payloads.dart';
import '../../../data/datasources/secure_key_datasource.dart';
import '../../../domain/entities/alarm.dart';
import '../../../domain/repositories/ble_repository.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

// --- Events ---
abstract class AlarmEvent extends Equatable {
  const AlarmEvent();
  @override
  List<Object?> get props => [];
}

class LoadAlarmsEvent extends AlarmEvent {}

class AddOrUpdateAlarmEvent extends AlarmEvent {
  final Alarm alarm;
  final BluetoothDevice? connectedDevice;

  /// When true, discard any stored secure key for this alarm id and mint a
  /// fresh one. Set this only when creating a *genuinely new* alarm (the id may
  /// be reused from a deleted alarm, and a fresh key stops an old printed QR
  /// from dismissing the new alarm). Leave false for edits, active-toggles and
  /// delete-undo, so a previously printed QR keeps working.
  final bool rotateSecureKey;

  const AddOrUpdateAlarmEvent(
    this.alarm,
    this.connectedDevice, {
    this.rotateSecureKey = false,
  });
  @override
  List<Object?> get props => [alarm, connectedDevice, rotateSecureKey];
}

class DeleteAlarmEvent extends AlarmEvent {
  final int alarmId;
  final BluetoothDevice? connectedDevice;
  const DeleteAlarmEvent(this.alarmId, this.connectedDevice);
  @override
  List<Object?> get props => [alarmId, connectedDevice];
}

class SyncAlarmsToDeviceEvent extends AlarmEvent {
  final BluetoothDevice connectedDevice;
  final Completer<void>? completer;
  const SyncAlarmsToDeviceEvent(this.connectedDevice, {this.completer});
  @override
  List<Object?> get props => [connectedDevice];
}

class SetRingingAlarmEvent extends AlarmEvent {
  final int? alarmId;
  const SetRingingAlarmEvent(this.alarmId);
  @override
  List<Object?> get props => [alarmId];
}

// --- State ---
class AlarmState extends Equatable {
  final List<Alarm> alarms;
  final Set<int> pendingDeleteIds;
  final int driftPpm;
  final bool isLoading;
  final int? ringingAlarmId;
  final String? syncError;

  const AlarmState({
    this.alarms = const [],
    this.pendingDeleteIds = const {},
    this.driftPpm = 0,
    this.isLoading = false,
    this.ringingAlarmId,
    this.syncError,
  });

  AlarmState copyWith({
    List<Alarm>? alarms,
    Set<int>? pendingDeleteIds,
    int? driftPpm,
    bool? isLoading,
    int? ringingAlarmId,
    String? syncError,
    bool clearRingingAlarm = false,
    bool clearSyncError = false,
  }) {
    return AlarmState(
      alarms: alarms ?? this.alarms,
      pendingDeleteIds: pendingDeleteIds ?? this.pendingDeleteIds,
      driftPpm: driftPpm ?? this.driftPpm,
      isLoading: isLoading ?? this.isLoading,
      ringingAlarmId: clearRingingAlarm
          ? null
          : (ringingAlarmId ?? this.ringingAlarmId),
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
    );
  }

  @override
  List<Object?> get props => [
    alarms,
    pendingDeleteIds,
    driftPpm,
    isLoading,
    ringingAlarmId,
    syncError,
  ];
}

// --- Bloc ---
class AlarmBloc extends Bloc<AlarmEvent, AlarmState> {
  final BleRepository bleRepository;
  final SharedPreferences prefs;
  final SecureKeyDatasource secureKeyDatasource;

  static const String _alarmsKey = 'saved_alarms';
  static const String _pendingDeletesKey = 'pending_alarm_deletes';

  /// The hardware clock only has room for this many alarm slots.
  static const int maxHardwareAlarms = 5;

  AlarmBloc({
    required this.bleRepository,
    required this.prefs,
    SecureKeyDatasource? secureKeyDatasource,
  }) : secureKeyDatasource = secureKeyDatasource ?? SecureKeyDatasource(),
       super(const AlarmState()) {
    on<LoadAlarmsEvent>(_onLoadAlarms);
    on<AddOrUpdateAlarmEvent>(_onAddOrUpdateAlarm);
    on<DeleteAlarmEvent>(_onDeleteAlarm);
    on<SyncAlarmsToDeviceEvent>(_onSyncAlarmsToDevice);
    on<SetRingingAlarmEvent>(_onSetRingingAlarm);
  }

  void _onLoadAlarms(LoadAlarmsEvent event, Emitter<AlarmState> emit) {
    emit(state.copyWith(isLoading: true));
    var loadedAlarms = const <Alarm>[];
    var pendingDeleteIds = const <int>{};

    try {
      final alarmsJson = prefs.getString(_alarmsKey);
      if (alarmsJson != null) {
        final List<dynamic> decoded = jsonDecode(alarmsJson);
        loadedAlarms = decoded
            .map((e) => Alarm.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    try {
      final pendingDeletesJson = prefs.getString(_pendingDeletesKey);
      if (pendingDeletesJson != null) {
        final List<dynamic> decoded = jsonDecode(pendingDeletesJson);
        pendingDeleteIds = decoded.map((id) => id as int).toSet();
      }
    } catch (_) {}

    emit(
      state.copyWith(
        alarms: loadedAlarms,
        pendingDeleteIds: pendingDeleteIds,
        isLoading: false,
      ),
    );
  }

  void _onSetRingingAlarm(
    SetRingingAlarmEvent event,
    Emitter<AlarmState> emit,
  ) {
    emit(
      state.copyWith(
        ringingAlarmId: event.alarmId,
        clearRingingAlarm: event.alarmId == null,
      ),
    );
  }

  void _onAddOrUpdateAlarm(
    AddOrUpdateAlarmEvent event,
    Emitter<AlarmState> emit,
  ) async {
    final updatedAlarms = List<Alarm>.from(state.alarms);
    final index = updatedAlarms.indexWhere((a) => a.id == event.alarm.id);
    if (index >= 0) {
      updatedAlarms[index] = event.alarm;
    } else {
      // Adding a brand-new alarm: the hardware only has [maxHardwareAlarms]
      // slots, so reject the add centrally (the UI guards too, but this is the
      // single source of truth and closes race/duplicate-tap gaps).
      if (updatedAlarms.length >= maxHardwareAlarms) {
        emit(
          state.copyWith(
            syncError:
                'The clock supports up to $maxHardwareAlarms alarms. '
                'Delete one before adding another.',
          ),
        );
        return;
      }
      updatedAlarms.add(event.alarm);
    }

    // Mint a fresh dismissal key for genuinely-new alarms so a stale QR from a
    // deleted alarm that reused this id can't dismiss it.
    if (event.rotateSecureKey) {
      try {
        await secureKeyDatasource.deleteKey(event.alarm.id);
      } catch (_) {}
    }

    final pendingDeletes = Set<int>.from(state.pendingDeleteIds)
      ..remove(event.alarm.id);

    emit(
      state.copyWith(
        alarms: updatedAlarms,
        pendingDeleteIds: pendingDeletes,
        clearSyncError: true,
      ),
    );
    await _saveAlarms(updatedAlarms);
    await _savePendingDeletes(pendingDeletes);

    if (event.connectedDevice == null) return;

    try {
      await _sendAlarmToDevice(event.connectedDevice!, event.alarm);
    } catch (_) {
      emit(
        state.copyWith(
          syncError:
              'Alarm saved locally, but it could not be synced to the clock.',
        ),
      );
    }
  }

  void _onDeleteAlarm(DeleteAlarmEvent event, Emitter<AlarmState> emit) async {
    final updatedAlarms = state.alarms
        .where((a) => a.id != event.alarmId)
        .toList();
    final pendingDeletes = Set<int>.from(state.pendingDeleteIds);

    emit(
      state.copyWith(
        alarms: updatedAlarms,
        pendingDeleteIds: pendingDeletes,
        clearSyncError: true,
      ),
    );
    await _saveAlarms(updatedAlarms);
    // NOTE: the secure key is intentionally *kept* here so a delete can be
    // undone (or re-printed) with the same QR still valid. A genuinely new
    // alarm that later reuses this id rotates the key instead — see
    // AddOrUpdateAlarmEvent.rotateSecureKey.

    if (event.connectedDevice == null) {
      pendingDeletes.add(event.alarmId);
      await _savePendingDeletes(pendingDeletes);
      emit(state.copyWith(pendingDeleteIds: pendingDeletes));
      return;
    }

    try {
      await bleRepository.sendCommand(event.connectedDevice!, 0x03, [
        event.alarmId & 0xFF,
      ]);
      pendingDeletes.remove(event.alarmId);
      await _savePendingDeletes(pendingDeletes);
      emit(state.copyWith(pendingDeleteIds: pendingDeletes));
    } catch (_) {
      pendingDeletes.add(event.alarmId);
      await _savePendingDeletes(pendingDeletes);
      emit(
        state.copyWith(
          pendingDeleteIds: pendingDeletes,
          syncError:
              'Alarm deleted locally, but the clock will be updated when it reconnects.',
        ),
      );
    }
  }

  Future<void> _onSyncAlarmsToDevice(
    SyncAlarmsToDeviceEvent event,
    Emitter<AlarmState> emit,
  ) async {
    try {
      var pendingDeletes = Set<int>.from(state.pendingDeleteIds);
      emit(state.copyWith(clearSyncError: true));

      for (final alarmId in state.pendingDeleteIds) {
        try {
          await bleRepository.sendCommand(event.connectedDevice, 0x03, [
            alarmId & 0xFF,
          ]);
          pendingDeletes.remove(alarmId);
        } catch (_) {
          const message =
              'Some deleted alarms could not be removed from the clock.';
          emit(state.copyWith(syncError: message));
          _completeSync(event.completer, error: Exception(message));
          return;
        }
      }

      await _savePendingDeletes(pendingDeletes);
      emit(state.copyWith(pendingDeleteIds: pendingDeletes));

      // The clock only has [maxHardwareAlarms] slots; sync the lowest ids so we
      // never overflow hardware storage even if more alarms exist locally.
      final alarmsToSync = (List<Alarm>.from(
        state.alarms,
      )..sort((a, b) => a.id.compareTo(b.id))).take(maxHardwareAlarms);
      for (final alarm in alarmsToSync) {
        try {
          await _sendAlarmToDevice(event.connectedDevice, alarm);
        } catch (_) {
          const message = 'Some alarms could not be synced to the clock.';
          emit(state.copyWith(syncError: message));
          _completeSync(event.completer, error: Exception(message));
          return;
        }
      }

      _completeSync(event.completer);
    } catch (e) {
      // A failure here (e.g. emit after the bloc is closed mid-sync) must still
      // complete the completer, otherwise callers awaiting it hang forever.
      _completeSync(event.completer, error: e);
    }
  }

  Future<void> _sendAlarmToDevice(BluetoothDevice device, Alarm alarm) async {
    await bleRepository.sendCommand(device, 0x02, BlePayloads.alarm(alarm));

    if (alarm.qrRequired) {
      final token = await secureKeyDatasource.getDailyToken(alarm.id);
      await bleRepository.sendCommand(device, 0x07, [
        alarm.id & 0xFF,
        ...token,
      ]);
    }
  }

  Future<void> _saveAlarms(List<Alarm> alarms) {
    final encoded = jsonEncode(alarms.map((a) => a.toJson()).toList());
    return prefs.setString(_alarmsKey, encoded);
  }

  Future<void> _savePendingDeletes(Set<int> pendingDeletes) {
    final ids = pendingDeletes.toList()..sort();
    return prefs.setString(_pendingDeletesKey, jsonEncode(ids));
  }

  void _completeSync(Completer<void>? completer, {Object? error}) {
    if (completer == null || completer.isCompleted) return;
    if (error != null) {
      completer.completeError(error);
    } else {
      completer.complete();
    }
  }
}
