import 'dart:async';
import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single app-side countdown mirror of a timer running on the clock. The
/// hardware runs the timer autonomously; this lets the app show how much time
/// is left and lets the user clear finished timers from the list.
class CountdownTimer extends Equatable {
  final int id;
  final String label;

  /// Wall-clock instant (ms since epoch) when the timer completes.
  final int endEpochMs;

  /// Total configured duration in seconds, kept for display/progress.
  final int totalSeconds;

  const CountdownTimer({
    required this.id,
    required this.label,
    required this.endEpochMs,
    required this.totalSeconds,
  });

  Duration remaining(DateTime now) {
    final ms = endEpochMs - now.millisecondsSinceEpoch;
    return ms <= 0 ? Duration.zero : Duration(milliseconds: ms);
  }

  bool isDone(DateTime now) => now.millisecondsSinceEpoch >= endEpochMs;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'endEpochMs': endEpochMs,
    'totalSeconds': totalSeconds,
  };

  factory CountdownTimer.fromJson(Map<String, dynamic> json) => CountdownTimer(
    id: json['id'] as int,
    label: (json['label'] as String?) ?? 'Timer',
    endEpochMs: json['endEpochMs'] as int,
    totalSeconds: (json['totalSeconds'] as int?) ?? 0,
  );

  @override
  List<Object?> get props => [id, label, endEpochMs, totalSeconds];
}

/// Holds the list of active timer mirrors. Persists across launches so a
/// countdown started before backgrounding the app is still shown on return.
class CountdownTimerCubit extends Cubit<List<CountdownTimer>> {
  final SharedPreferences prefs;
  static const String _key = 'active_timers';

  CountdownTimerCubit({required this.prefs}) : super(const []) {
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
      final timers = decoded
          .map((e) => CountdownTimer.fromJson(e as Map<String, dynamic>))
          .toList();
      emit(timers);
    } catch (_) {
      emit(const []);
    }
  }

  void _persist(List<CountdownTimer> timers) {
    // Fire-and-forget, but never let a SharedPreferences failure surface as an
    // unhandled async exception.
    unawaited(
      prefs
          .setString(_key, jsonEncode(timers.map((t) => t.toJson()).toList()))
          .catchError((Object _) => false),
    );
  }

  /// Registers a timer of [duration] (matching a `0x0A` command sent to the
  /// clock). [label] is an optional user-facing name.
  void startTimer(Duration duration, {String label = 'Timer'}) {
    final now = DateTime.now();
    final usedIds = state.map((t) => t.id).toSet();
    var id = 1;
    while (usedIds.contains(id)) {
      id++;
    }
    final timer = CountdownTimer(
      id: id,
      label: label.trim().isEmpty ? 'Timer' : label.trim(),
      endEpochMs: now.millisecondsSinceEpoch + duration.inMilliseconds,
      totalSeconds: duration.inSeconds,
    );
    final updated = [...state, timer]
      ..sort((a, b) => a.endEpochMs.compareTo(b.endEpochMs));
    emit(updated);
    _persist(updated);
  }

  /// Removes a timer from the app's view (e.g. after it finishes, or when the
  /// user clears it). Does not stop the hardware timer — the clock has no
  /// cancel command in the current firmware protocol.
  void removeTimer(int id) {
    final updated = state.where((t) => t.id != id).toList();
    emit(updated);
    _persist(updated);
  }
}
