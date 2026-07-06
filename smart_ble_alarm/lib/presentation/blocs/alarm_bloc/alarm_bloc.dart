import 'dart:async';
import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/ble/ble_payloads.dart';
import '../../../core/notifications/notification_service.dart';
import '../../../data/datasources/secure_key_datasource.dart';
import '../../../domain/entities/alarm.dart';
import '../../../domain/repositories/ble_repository.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Whether an alarm's current settings are actually programmed into the clock.
///
/// With on-demand BLE the app is often disconnected while alarms are edited, so
/// "saved locally" and "live on the hardware" can diverge — this makes that
/// state visible instead of silently pretending every alarm will ring.
enum AlarmSyncStatus {
  /// The clock has confirmed this alarm's current settings.
  synced,

  /// Saved on the phone but not yet uploaded (never synced, edited since the
  /// last sync, or waiting for the clock to reconnect).
  pending,

  /// The most recent attempt to write this alarm to the clock failed.
  failed,
}

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

  /// Per-alarm fingerprint (id → [Alarm.syncHash]) of the settings the clock has
  /// most recently confirmed. Compared against each alarm's current hash to tell
  /// whether it is live on the hardware. Persisted across launches.
  final Map<int, int> syncedHashes;

  /// Alarm ids whose most recent write to the clock failed. Transient (not
  /// persisted): a failure is meaningful only for the current session; on the
  /// next launch such an alarm simply reads as [AlarmSyncStatus.pending].
  final Set<int> syncFailedIds;

  final int driftPpm;
  final bool isLoading;
  final int? ringingAlarmId;
  final String? syncError;

  const AlarmState({
    this.alarms = const [],
    this.pendingDeleteIds = const {},
    this.syncedHashes = const {},
    this.syncFailedIds = const {},
    this.driftPpm = 0,
    this.isLoading = false,
    this.ringingAlarmId,
    this.syncError,
  });

  AlarmState copyWith({
    List<Alarm>? alarms,
    Set<int>? pendingDeleteIds,
    Map<int, int>? syncedHashes,
    Set<int>? syncFailedIds,
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
      syncedHashes: syncedHashes ?? this.syncedHashes,
      syncFailedIds: syncFailedIds ?? this.syncFailedIds,
      driftPpm: driftPpm ?? this.driftPpm,
      isLoading: isLoading ?? this.isLoading,
      ringingAlarmId: clearRingingAlarm
          ? null
          : (ringingAlarmId ?? this.ringingAlarmId),
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
    );
  }

  /// How [alarm]'s current settings compare to what the clock has confirmed.
  AlarmSyncStatus syncStatusFor(Alarm alarm) {
    if (syncFailedIds.contains(alarm.id)) return AlarmSyncStatus.failed;
    if (syncedHashes[alarm.id] == alarm.syncHash) return AlarmSyncStatus.synced;
    return AlarmSyncStatus.pending;
  }

  /// Count of alarms whose settings are confirmed live on the clock.
  int get syncedAlarmCount =>
      alarms.where((a) => syncStatusFor(a) == AlarmSyncStatus.synced).length;

  @override
  List<Object?> get props => [
    alarms,
    pendingDeleteIds,
    syncedHashes,
    syncFailedIds,
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

  /// Optional phone-side backup scheduler. Injected in production; left null in
  /// tests so the bloc has no platform-channel dependency. Every change to the
  /// alarm set is mirrored to it so a dead/out-of-range clock still wakes the
  /// user.
  final NotificationService? notificationService;

  static const String _alarmsKey = 'saved_alarms';
  static const String _pendingDeletesKey = 'pending_alarm_deletes';
  static const String _syncedHashesKey = 'synced_alarm_hashes';

  /// Version of the persisted [_alarmsKey] envelope. Bump when the stored shape
  /// changes so [_onLoadAlarms] can migrate older data instead of dropping it.
  /// v1 = a bare JSON list (no envelope); v2 = `{"version":2,"alarms":[...]}`.
  static const int _alarmsSchemaVersion = 2;

  /// The hardware clock only has room for this many alarm slots.
  static const int maxHardwareAlarms = 5;

  AlarmBloc({
    required this.bleRepository,
    required this.prefs,
    SecureKeyDatasource? secureKeyDatasource,
    this.notificationService,
  }) : secureKeyDatasource = secureKeyDatasource ?? SecureKeyDatasource(),
       super(const AlarmState()) {
    // Process every alarm event to completion before starting the next. Bloc's
    // default (concurrent) transformer lets two handlers interleave across their
    // `await`s — each snapshots a Set/Map from `state` before awaiting a BLE
    // write, then emits that stale snapshot afterwards, silently clobbering the
    // other handler's pending-delete / sync-status updates. Serialising the
    // handlers removes that race entirely (none of them await a sibling event,
    // so there is no deadlock risk).
    on<LoadAlarmsEvent>(_onLoadAlarms, transformer: _sequential());
    on<AddOrUpdateAlarmEvent>(_onAddOrUpdateAlarm, transformer: _sequential());
    on<DeleteAlarmEvent>(_onDeleteAlarm, transformer: _sequential());
    on<SyncAlarmsToDeviceEvent>(
      _onSyncAlarmsToDevice,
      transformer: _sequential(),
    );
    on<SetRingingAlarmEvent>(_onSetRingingAlarm, transformer: _sequential());
  }

  /// Serialising event transformer: runs one handler's stream to completion
  /// before mapping the next event. Prevents the emit-stale-snapshot race
  /// described in the constructor.
  static EventTransformer<E> _sequential<E>() =>
      (events, mapper) => events.asyncExpand(mapper);

  void _onLoadAlarms(LoadAlarmsEvent event, Emitter<AlarmState> emit) {
    emit(state.copyWith(isLoading: true));
    var loadedAlarms = const <Alarm>[];
    var pendingDeleteIds = const <int>{};
    var syncedHashes = const <int, int>{};

    try {
      loadedAlarms = parseStoredAlarms(prefs.getString(_alarmsKey));
    } catch (_) {}

    try {
      final pendingDeletesJson = prefs.getString(_pendingDeletesKey);
      if (pendingDeletesJson != null) {
        final List<dynamic> decoded = jsonDecode(pendingDeletesJson);
        pendingDeleteIds = decoded.map((id) => id as int).toSet();
      }
    } catch (_) {}

    try {
      final syncedHashesJson = prefs.getString(_syncedHashesKey);
      if (syncedHashesJson != null) {
        final Map<String, dynamic> decoded = jsonDecode(syncedHashesJson);
        syncedHashes = decoded.map(
          (id, hash) => MapEntry(int.parse(id), hash as int),
        );
      }
    } catch (_) {}

    emit(
      state.copyWith(
        alarms: loadedAlarms,
        pendingDeleteIds: pendingDeleteIds,
        syncedHashes: syncedHashes,
        isLoading: false,
      ),
    );
    _rescheduleBackupAlarms(loadedAlarms);
  }

  Future<void> _onSetRingingAlarm(
    SetRingingAlarmEvent event,
    Emitter<AlarmState> emit,
  ) async {
    // An alarm just stopped ringing — either the user dismissed it (QR/item
    // scan) or the clock reported it stopped (0x89). If the alarm that was
    // ringing is a one-time alarm (no repeat days), disable it in the app so it
    // doesn't linger as "active" after it has already fired.
    if (event.alarmId == null && state.ringingAlarmId != null) {
      final index = state.alarms.indexWhere(
        (a) => a.id == state.ringingAlarmId,
      );
      if (index >= 0) {
        final ringing = state.alarms[index];
        final isOneTime = (ringing.dayMask & 0x7F) == 0;
        if (isOneTime && ringing.isActive) {
          final updatedAlarms = List<Alarm>.from(state.alarms);
          // Clear the 0x80 "active" bit; one-time alarms carry no day bits, so
          // this leaves an inactive alarm the user can re-enable later.
          updatedAlarms[index] = ringing.copyWith(
            dayMask: ringing.dayMask & 0x7F,
          );
          emit(
            state.copyWith(alarms: updatedAlarms, clearRingingAlarm: true),
          );
          await _saveAlarms(updatedAlarms);
          _rescheduleBackupAlarms(updatedAlarms);
          return;
        }
      }
    }

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
    // Refresh the phone-side backup regardless of clock connectivity — this is
    // the fallback for exactly the case where the clock isn't reachable.
    _rescheduleBackupAlarms(updatedAlarms);

    if (event.connectedDevice == null) return;

    try {
      await _sendAlarmToDevice(event.connectedDevice!, event.alarm);
      // Confirmed on the hardware: record the fingerprint and clear any prior
      // failure so the UI can show this alarm as live on the clock.
      final syncedHashes = Map<int, int>.from(state.syncedHashes)
        ..[event.alarm.id] = event.alarm.syncHash;
      final syncFailedIds = Set<int>.from(state.syncFailedIds)
        ..remove(event.alarm.id);
      await _saveSyncedHashes(syncedHashes);
      emit(
        state.copyWith(
          syncedHashes: syncedHashes,
          syncFailedIds: syncFailedIds,
        ),
      );
    } catch (_) {
      final syncFailedIds = Set<int>.from(state.syncFailedIds)
        ..add(event.alarm.id);
      emit(
        state.copyWith(
          syncFailedIds: syncFailedIds,
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
    // Drop any sync-status tracking for the removed id so a future alarm that
    // reuses it can't inherit a stale "synced" fingerprint.
    final syncedHashes = Map<int, int>.from(state.syncedHashes)
      ..remove(event.alarmId);
    final syncFailedIds = Set<int>.from(state.syncFailedIds)
      ..remove(event.alarmId);

    emit(
      state.copyWith(
        alarms: updatedAlarms,
        pendingDeleteIds: pendingDeletes,
        syncedHashes: syncedHashes,
        syncFailedIds: syncFailedIds,
        clearSyncError: true,
      ),
    );
    await _saveAlarms(updatedAlarms);
    await _saveSyncedHashes(syncedHashes);
    // Drop this alarm's phone-side backup so a deleted alarm can't keep ringing
    // the notification fallback.
    _rescheduleBackupAlarms(updatedAlarms);
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
      final syncedHashes = Map<int, int>.from(state.syncedHashes);
      final syncFailedIds = Set<int>.from(state.syncFailedIds);
      for (final alarm in alarmsToSync) {
        try {
          await _sendAlarmToDevice(event.connectedDevice, alarm);
          // Confirmed live on the hardware — fingerprint it and clear failure.
          syncedHashes[alarm.id] = alarm.syncHash;
          syncFailedIds.remove(alarm.id);
        } catch (_) {
          syncFailedIds.add(alarm.id);
          const message = 'Some alarms could not be synced to the clock.';
          await _saveSyncedHashes(syncedHashes);
          emit(
            state.copyWith(
              syncedHashes: syncedHashes,
              syncFailedIds: syncFailedIds,
              syncError: message,
            ),
          );
          _completeSync(event.completer, error: Exception(message));
          return;
        }
      }

      await _saveSyncedHashes(syncedHashes);
      emit(
        state.copyWith(
          syncedHashes: syncedHashes,
          syncFailedIds: syncFailedIds,
        ),
      );
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
    return prefs.setString(_alarmsKey, encodeStoredAlarms(alarms));
  }

  /// Serialise alarms into the versioned storage envelope so future shape
  /// changes can be migrated on load rather than silently dropped. Exposed for
  /// tests. See [_alarmsSchemaVersion].
  static String encodeStoredAlarms(List<Alarm> alarms) => jsonEncode({
    'version': _alarmsSchemaVersion,
    'alarms': alarms.map((a) => a.toJson()).toList(),
  });

  /// Parse the persisted alarms string, accepting both the legacy v1 shape (a
  /// bare list, no envelope) and the v2 `{"version":n,"alarms":[...]}` envelope.
  /// Unknown future versions still read the alarms array; additive field
  /// changes are absorbed by the per-field defaults in [Alarm.fromJson].
  /// Exposed for tests.
  static List<Alarm> parseStoredAlarms(String? alarmsJson) {
    if (alarmsJson == null) return const [];
    final decoded = jsonDecode(alarmsJson);
    final List<dynamic> rawAlarms;
    if (decoded is List) {
      rawAlarms = decoded;
    } else if (decoded is Map<String, dynamic>) {
      rawAlarms = (decoded['alarms'] as List<dynamic>?) ?? const [];
    } else {
      rawAlarms = const [];
    }
    return rawAlarms
        .map((e) => Alarm.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Mirror the current alarm set to the phone-side backup scheduler. Fire and
  /// forget: the notification is a safety net, never the source of truth, so a
  /// failure here must not block a save or a BLE write.
  void _rescheduleBackupAlarms(List<Alarm> alarms) {
    final pending = notificationService?.syncAlarms(alarms);
    if (pending != null) unawaited(pending);
  }

  Future<void> _savePendingDeletes(Set<int> pendingDeletes) {
    final ids = pendingDeletes.toList()..sort();
    return prefs.setString(_pendingDeletesKey, jsonEncode(ids));
  }

  Future<void> _saveSyncedHashes(Map<int, int> syncedHashes) {
    // JSON object keys must be strings; ids are parsed back on load.
    final encoded = syncedHashes.map((id, hash) => MapEntry('$id', hash));
    return prefs.setString(_syncedHashesKey, jsonEncode(encoded));
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
