import 'dart:async';
import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One recorded alarm dismissal. Useful for narcolepsy users (and their
/// clinicians) to see when alarms fired and how they were cleared over time.
class DismissalRecord extends Equatable {
  final int alarmId;

  /// When the dismissal completed (ms since epoch).
  final int epochMs;

  /// 'QR' or 'Item'.
  final String method;

  /// Optional alarm label at the time of dismissal.
  final String? label;

  const DismissalRecord({
    required this.alarmId,
    required this.epochMs,
    required this.method,
    this.label,
  });

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(epochMs);

  Map<String, dynamic> toJson() => {
    'alarmId': alarmId,
    'epochMs': epochMs,
    'method': method,
    if (label != null) 'label': label,
  };

  factory DismissalRecord.fromJson(Map<String, dynamic> json) =>
      DismissalRecord(
        alarmId: json['alarmId'] as int,
        epochMs: json['epochMs'] as int,
        method: (json['method'] as String?) ?? 'QR',
        label: json['label'] as String?,
      );

  @override
  List<Object?> get props => [alarmId, epochMs, method, label];
}

/// Persistent, capped log of completed dismissals (newest first).
class DismissalHistoryCubit extends Cubit<List<DismissalRecord>> {
  final SharedPreferences prefs;
  static const String _key = 'dismissal_history';
  static const int _maxEntries = 100;

  DismissalHistoryCubit({required this.prefs}) : super(const []) {
    _load();
  }

  void _load() {
    try {
      final raw = prefs.getString(_key);
      if (raw == null) {
        emit(const []);
        return;
      }
      final List<dynamic> decoded = jsonDecode(raw);
      emit(
        decoded
            .map((e) => DismissalRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    } catch (_) {
      emit(const []);
    }
  }

  void _persist(List<DismissalRecord> records) {
    // Fire-and-forget, but never let a SharedPreferences failure surface as an
    // unhandled async exception.
    unawaited(
      prefs
          .setString(_key, jsonEncode(records.map((r) => r.toJson()).toList()))
          .catchError((Object _) => false),
    );
  }

  /// Records a completed dismissal at the top of the log, trimming to the most
  /// recent [_maxEntries].
  void record({required int alarmId, required String method, String? label}) {
    final entry = DismissalRecord(
      alarmId: alarmId,
      epochMs: DateTime.now().millisecondsSinceEpoch,
      method: method,
      label: label,
    );
    final updated = [entry, ...state];
    if (updated.length > _maxEntries) {
      updated.removeRange(_maxEntries, updated.length);
    }
    emit(updated);
    _persist(updated);
  }

  void clear() {
    emit(const []);
    _persist(const []);
  }
}
