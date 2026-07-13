import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// Best-effort keep-screen-awake while the phone is ringing. Try-caught so a
// missing platform impl (tests/desktop) can never crash the ring.
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:smart_ble_alarm/core/audio/alarm_tone_player.dart';
import 'package:smart_ble_alarm/core/ui/wake_haptics.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';

/// The "Ring on this phone" engine — an invisible widget mounted app-wide (over
/// every tab, alongside the ringing banner) that makes the *primary* phone ring
/// itself when an alarm's time arrives, independent of the hardware clock.
///
/// It has two jobs:
///  1. **Originate** a ring: a 1-second ticker watches the wall clock and, when
///     an enabled alarm falls on the current minute and nothing is already
///     ringing, dispatches [SetRingingAlarmEvent] so the shared banner/cards +
///     RingingDismissal wake-challenge flow light up across the app.
///  2. **Sound** a ring: whenever an alarm is ringing (this phone's own trigger
///     *or* a hardware clock's 0x08 relayed into [AlarmState.ringingAlarmId])
///     and the setting is on, it loops the alarm tone at the alarm's volume with
///     a gradual-wake fade and pulsing haptics, and holds the screen awake.
///
/// **Honest scope (Beta):** this is a foreground engine. It rings reliably while
/// the app is open (or reopened via the backup notification). It cannot wake the
/// device and start a fresh ring while the app is force-closed or fully
/// suspended — especially on iOS, where background timers don't fire. That gap
/// is covered by the separate "Backup notifications" layer, and the hardware
/// WakeGuard clock remains the tamper-proof guarantee. Dismissal always runs the
/// alarm's wake challenge; there is deliberately no free "dismiss anyway".
class PhoneAlarmRinger extends StatefulWidget {
  const PhoneAlarmRinger({super.key});

  @override
  State<PhoneAlarmRinger> createState() => _PhoneAlarmRingerState();
}

class _PhoneAlarmRingerState extends State<PhoneAlarmRinger>
    with WidgetsBindingObserver {
  final AlarmTonePlayer _tone = AlarmTonePlayer();
  Timer? _ticker;
  Timer? _ringHaptic;

  /// The alarm id currently sounding *on this phone*. Tracks the tone/haptics/
  /// wakelock lifecycle so reconciling against the shared ring state is a no-op
  /// when nothing changed (the clock re-broadcasts 0x08 every second).
  int? _audioAlarmId;

  /// Per-minute guard so a matched alarm fires exactly once per occurrence even
  /// though the ticker runs every second. [_firedMinuteToken] is the calendar
  /// minute the ids belong to; it resets the set when the minute rolls over.
  String? _firedMinuteToken;
  final Set<int> _firedAlarmIds = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _ringHaptic?.cancel();
    _tone.dispose();
    _releaseWakelock();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground (e.g. after tapping the backup
    // notification): re-check immediately rather than waiting up to a second, so
    // an alarm firing this exact minute rings without a visible delay.
    if (state == AppLifecycleState.resumed) _tick();
  }

  bool get _enabled {
    if (!mounted) return false;
    return context.read<SettingsBloc>().state.phoneAlarmEnabled;
  }

  void _tick() {
    if (!mounted || !_enabled) return;
    final now = DateTime.now();
    final token = _minuteToken(now);
    if (_firedMinuteToken != token) {
      _firedMinuteToken = token;
      _firedAlarmIds.clear();
    }
    final alarmBloc = context.read<AlarmBloc>();
    // Only originate a ring when nothing is already sounding (the hardware
    // clock's 0x08 path may have set it first; the guard keeps the two engines
    // from double-triggering the same alarm).
    if (alarmBloc.state.ringingAlarmId != null) return;
    final alarm = _matchingUnfiredAlarm(alarmBloc.state.alarms, now);
    if (alarm == null) return;
    _firedAlarmIds.add(alarm.id);
    // Sounding starts in the BlocListener reacting to the new ringing state, so
    // a hardware-clock-originated ring and a phone-originated one share one path.
    alarmBloc.add(SetRingingAlarmEvent(alarm.id));
  }

  /// First active alarm scheduled for [now]'s hour:minute (and weekday, for a
  /// repeat alarm) that hasn't already fired this minute. Mirrors the Dedicated
  /// Clock's matching rules so both engines agree on when an alarm is "due".
  Alarm? _matchingUnfiredAlarm(List<Alarm> alarms, DateTime now) {
    for (final alarm in alarms) {
      if (!alarm.isActive) continue;
      if (alarm.hour != now.hour || alarm.minute != now.minute) continue;
      // Repeat alarms fire only on their configured weekdays; a one-time alarm
      // (no repeat bits) fires at its time on whatever day it stays enabled.
      if (_hasRepeatDays(alarm) && !alarm.isDayActive(now.weekday % 7)) continue;
      if (_firedAlarmIds.contains(alarm.id)) continue;
      return alarm;
    }
    return null;
  }

  String _minuteToken(DateTime t) =>
      '${t.year}-${t.month}-${t.day}-${t.hour}-${t.minute}';

  bool _hasRepeatDays(Alarm alarm) => (alarm.dayMask & 0x7F) != 0;

  /// Bring the tone/haptics/wakelock in line with the desired ringing alarm:
  /// [desired] is the alarm id that should be sounding on this phone, or null
  /// for silence. Idempotent — repeated calls with the same id do nothing.
  void _reconcile(int? desired, List<Alarm> alarms) {
    if (desired == _audioAlarmId) return;

    if (desired == null) {
      _audioAlarmId = null;
      _ringHaptic?.cancel();
      _ringHaptic = null;
      unawaited(_tone.stop());
      _releaseWakelock();
      return;
    }

    Alarm? alarm;
    for (final a in alarms) {
      if (a.id == desired) {
        alarm = a;
        break;
      }
    }
    if (alarm == null) return; // ringing id with no matching alarm — ignore.

    _audioAlarmId = desired;
    _acquireWakelock();
    WakeHaptics.heavyImpact();
    _ringHaptic?.cancel();
    _ringHaptic = Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => WakeHaptics.heavyImpact(),
    );
    unawaited(_tone.play(alarm));
  }

  Future<void> _acquireWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {}
  }

  Future<void> _releaseWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Drive audio purely from (setting enabled) × (something is ringing). A
    // SettingsBloc listener re-reconciles when the toggle flips mid-ring so
    // turning it off silences the phone at once.
    return BlocListener<SettingsBloc, SettingsState>(
      listenWhen: (prev, curr) =>
          prev.phoneAlarmEnabled != curr.phoneAlarmEnabled,
      listener: (context, settings) {
        final ringing = context.read<AlarmBloc>().state;
        _reconcile(
          settings.phoneAlarmEnabled ? ringing.ringingAlarmId : null,
          ringing.alarms,
        );
      },
      child: BlocListener<AlarmBloc, AlarmState>(
        listenWhen: (prev, curr) => prev.ringingAlarmId != curr.ringingAlarmId,
        listener: (context, alarmState) {
          final enabled = context.read<SettingsBloc>().state.phoneAlarmEnabled;
          _reconcile(
            enabled ? alarmState.ringingAlarmId : null,
            alarmState.alarms,
          );
        },
        child: const SizedBox.shrink(),
      ),
    );
  }
}
