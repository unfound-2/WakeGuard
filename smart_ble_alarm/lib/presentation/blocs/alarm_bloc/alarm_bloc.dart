import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  const AddOrUpdateAlarmEvent(this.alarm, this.connectedDevice);
  @override
  List<Object?> get props => [alarm, connectedDevice];
}

class DeleteAlarmEvent extends AlarmEvent {
  final int alarmId;
  final BluetoothDevice? connectedDevice;
  const DeleteAlarmEvent(this.alarmId, this.connectedDevice);
  @override
  List<Object?> get props => [alarmId, connectedDevice];
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
  final int driftPpm;
  final bool isLoading;
  final int? ringingAlarmId;

  const AlarmState({
    this.alarms = const [],
    this.driftPpm = 0,
    this.isLoading = false,
    this.ringingAlarmId,
  });

  AlarmState copyWith({
    List<Alarm>? alarms,
    int? driftPpm,
    bool? isLoading,
    int? ringingAlarmId,
    bool clearRingingAlarm = false,
  }) {
    return AlarmState(
      alarms: alarms ?? this.alarms,
      driftPpm: driftPpm ?? this.driftPpm,
      isLoading: isLoading ?? this.isLoading,
      ringingAlarmId: clearRingingAlarm ? null : (ringingAlarmId ?? this.ringingAlarmId),
    );
  }

  @override
  List<Object?> get props => [alarms, driftPpm, isLoading, ringingAlarmId];
}

// --- Bloc ---
class AlarmBloc extends Bloc<AlarmEvent, AlarmState> {
  final BleRepository bleRepository;
  final SharedPreferences prefs;

  static const String _alarmsKey = 'saved_alarms';

  AlarmBloc({required this.bleRepository, required this.prefs}) : super(const AlarmState()) {
    on<LoadAlarmsEvent>(_onLoadAlarms);
    on<AddOrUpdateAlarmEvent>(_onAddOrUpdateAlarm);
    on<DeleteAlarmEvent>(_onDeleteAlarm);
    on<SetRingingAlarmEvent>(_onSetRingingAlarm);
  }

  void _onLoadAlarms(LoadAlarmsEvent event, Emitter<AlarmState> emit) {
    emit(state.copyWith(isLoading: true));
    try {
      final alarmsJson = prefs.getString(_alarmsKey);
      if (alarmsJson != null) {
        final List<dynamic> decoded = jsonDecode(alarmsJson);
        final alarms = decoded.map((e) => Alarm.fromJson(e as Map<String, dynamic>)).toList();
        emit(state.copyWith(alarms: alarms, isLoading: false));
        return;
      }
    } catch (_) {}
    emit(state.copyWith(isLoading: false));
  }

  void _onSetRingingAlarm(SetRingingAlarmEvent event, Emitter<AlarmState> emit) {
    emit(state.copyWith(
      ringingAlarmId: event.alarmId,
      clearRingingAlarm: event.alarmId == null,
    ));
  }

  void _onAddOrUpdateAlarm(AddOrUpdateAlarmEvent event, Emitter<AlarmState> emit) async {
    final updatedAlarms = List<Alarm>.from(state.alarms);
    final index = updatedAlarms.indexWhere((a) => a.id == event.alarm.id);
    if (index >= 0) {
      updatedAlarms[index] = event.alarm;
    } else {
      updatedAlarms.add(event.alarm);
    }

    emit(state.copyWith(alarms: updatedAlarms));
    _saveAlarms(updatedAlarms);

    if (event.connectedDevice != null) {
      // CMD 0x02: ALARM_DB_ADD
      List<int> payload = [
        event.alarm.id,
        event.alarm.hour,
        event.alarm.minute,
        event.alarm.dayMask,
        event.alarm.qrRequired ? 1 : 0
      ];
      try {
        await bleRepository.sendCommand(event.connectedDevice!, 0x02, payload);
      } catch (e) {
        // Handle failure to send
      }
    }
  }

  void _onDeleteAlarm(DeleteAlarmEvent event, Emitter<AlarmState> emit) async {
    final updatedAlarms = state.alarms.where((a) => a.id != event.alarmId).toList();
    emit(state.copyWith(alarms: updatedAlarms));
    _saveAlarms(updatedAlarms);

    if (event.connectedDevice != null) {
      // CMD 0x03: ALARM_DB_DEL
      try {
        await bleRepository.sendCommand(event.connectedDevice!, 0x03, [event.alarmId]);
      } catch (e) {
        // Handle failure to send
      }
    }
  }

  void _saveAlarms(List<Alarm> alarms) {
    final encoded = jsonEncode(alarms.map((a) => a.toJson()).toList());
    prefs.setString(_alarmsKey, encoded);
  }
}
