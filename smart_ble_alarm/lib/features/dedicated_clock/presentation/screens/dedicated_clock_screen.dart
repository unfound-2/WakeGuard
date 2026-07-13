import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// Best-effort keep-screen-awake. Wrapped in try/catch everywhere so a missing
// platform implementation (e.g. in widget tests) can never crash the clock.
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:smart_ble_alarm/core/audio/alarm_tone_player.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/core/ui/wake_haptics.dart';
import 'package:smart_ble_alarm/core/utils/alarm_time_utils.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/widgets/ringing_dismissal.dart';

/// Full-screen "Dedicated Clock" — turns a spare phone/tablet into a standby
/// bedside WakeGuard clock. It shows a large clock face, keeps the screen awake
/// while it is the foreground screen, and rings in the morning by reusing the
/// same wake-challenge dismissal as the hardware clock ([RingingDismissal]).
///
/// This is a **Beta** best-effort clock: it rings reliably only while the app is
/// open and the device is awake (the intended scenario — a device left plugged
/// in on the nightstand). Reliable ringing when the app is force-closed or the
/// screen is fully off (especially on iOS) is the staged phone-alarm background
/// engine; the hardware WakeGuard clock remains the tamper-proof guarantee.
class DedicatedClockScreen extends StatefulWidget {
  /// Leaves Dedicated Clock mode and returns the app to normal routing. Wired in
  /// `main.dart` to clear the persisted `dedicatedClockEnabled` flag.
  final VoidCallback? onExit;

  const DedicatedClockScreen({super.key, this.onExit});

  @override
  State<DedicatedClockScreen> createState() => _DedicatedClockScreenState();
}

class _DedicatedClockScreenState extends State<DedicatedClockScreen> {
  Timer? _ticker;
  Timer? _ringHaptic;
  DateTime _now = DateTime.now();

  /// Loops the synthesized alarm tone while ringing (shared engine, so the
  /// loudness/fade match the "Ring on this phone" path). Best-effort: a missing
  /// audio platform impl never crashes the clock.
  final AlarmTonePlayer _tone = AlarmTonePlayer();
  Timer? _snoozeTimer; // re-arms the ring after a snooze
  int _snoozesUsed = 0; // reset each fresh ring; gates the snooze button

  /// The alarm currently sounding on this device (drives the ring overlay). Null
  /// while the clock is idle. Local to this screen — there is no hardware clock
  /// pushing 0x08, so the dedicated clock owns its own ring state.
  Alarm? _ringing;
  DateTime? _ringingSince;

  /// Guards against re-firing the same alarm every tick within its minute.
  /// [_firedMinuteToken] is the calendar minute the ids below belong to; when
  /// the minute changes the set is cleared so each new occurrence rings once.
  /// Tracking the fired ids per-minute (rather than a single last-fired key)
  /// lets several alarms that share the same minute each be recognized as "not
  /// yet fired" — so a second coincident alarm is never lost when the first is
  /// dismissed after the calendar minute has already rolled over.
  String? _firedMinuteToken;
  final Set<int> _firedAlarmIds = <int>{};

  @override
  void initState() {
    super.initState();
    _enableWakelock();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ringHaptic?.cancel();
    _snoozeTimer?.cancel();
    _tone.dispose();
    _disableWakelock();
    super.dispose();
  }

  Future<void> _enableWakelock() async {
    try {
      await WakelockPlus.enable();
    } catch (_) {
      // Platform impl missing (tests/desktop) — the clock still works, the
      // screen just isn't force-kept-on.
    }
  }

  Future<void> _disableWakelock() async {
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  void _tick() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() => _now = now);
    if (_ringing != null) return; // already sounding — don't stack rings
    _maybeFire(now);
  }

  /// If an enabled alarm falls on this exact minute (and today), start ringing.
  void _maybeFire(DateTime now) {
    final token = _minuteToken(now);
    if (_firedMinuteToken != token) {
      // New minute — forget the previous minute's fired ids.
      _firedMinuteToken = token;
      _firedAlarmIds.clear();
    }
    final alarm = _matchingUnfiredAlarm(now.hour, now.minute, now);
    if (alarm == null) return;
    _firedAlarmIds.add(alarm.id);
    _startRing(alarm);
  }

  /// The first active alarm scheduled for [hour]:[minute] on [dayRef]'s weekday
  /// that has not already fired this minute, or null if none remain. Shared by
  /// [_maybeFire] and [_ringNextCoincidentOrClear] so both apply the same
  /// active/repeat-day/already-fired rules.
  Alarm? _matchingUnfiredAlarm(int hour, int minute, DateTime dayRef) {
    final alarms = context.read<AlarmBloc>().state.alarms;
    for (final alarm in alarms) {
      if (!alarm.isActive) continue;
      if (alarm.hour != hour || alarm.minute != minute) continue;
      // Repeat alarms fire only on their configured weekdays; a one-time alarm
      // (no repeat bits) fires at its time each day it stays enabled.
      if (_hasRepeatDays(alarm) && !alarm.isDayActive(dayRef.weekday % 7)) {
        continue;
      }
      if (_firedAlarmIds.contains(alarm.id)) continue;
      return alarm;
    }
    return null;
  }

  String _minuteToken(DateTime t) =>
      '${t.year}-${t.month}-${t.day}-${t.hour}-${t.minute}';

  bool _hasRepeatDays(Alarm alarm) => (alarm.dayMask & 0x7F) != 0;

  void _startRing(Alarm alarm, {bool fromSnooze = false}) {
    if (!fromSnooze) {
      _snoozesUsed = 0;
      _ringingSince = DateTime.now();
    } else {
      _ringingSince ??= DateTime.now();
    }
    setState(() => _ringing = alarm);
    WakeHaptics.heavyImpact();
    // Pulse the haptics alongside the looping tone as a stronger wake cue.
    _ringHaptic?.cancel();
    _ringHaptic = Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => WakeHaptics.heavyImpact(),
    );
    unawaited(_tone.play(alarm));
  }

  Future<void> _stopRing() async {
    _ringHaptic?.cancel();
    await _tone.stop();
  }

  Future<void> _handleDismiss(Alarm alarm) async {
    // Reuse the same task-aware dismissal UI, but verify locally: Dedicated
    // Clock mode may run on a spare phone/tablet with no BLE clock connected.
    // Keep sounding until the challenge succeeds; backing out leaves the local
    // ring active.
    final dismissed = await RingingDismissal.trigger(
      context,
      alarm,
      localOnly: true,
      ringingSince: _ringingSince,
    );
    if (!dismissed || !mounted) return;

    _snoozeTimer?.cancel();
    await _stopRing();
    if (!mounted) return;
    _disableOneTimeIfNeeded(alarm);
    _ringNextCoincidentOrClear(alarm);
  }

  /// After the current ring ends (dismissed or snoozed), ring any OTHER active
  /// alarm scheduled for this same minute that has not yet fired — so coincident
  /// alarms are never lost, even once the calendar minute has rolled past and
  /// [_maybeFire]'s minute check would no longer match. If none remain, drop
  /// back to the idle clock face and resume normal ticking.
  void _ringNextCoincidentOrClear(Alarm current) {
    final next = _matchingUnfiredAlarm(
      current.hour,
      current.minute,
      DateTime.now(),
    );
    if (next != null) {
      _firedAlarmIds.add(next.id);
      _startRing(next);
      return;
    }
    setState(() {
      _ringing = null;
      _ringingSince = null;
    });
  }

  void _disableOneTimeIfNeeded(Alarm alarm) {
    if (_hasRepeatDays(alarm) || !alarm.isActive) return;
    context.read<AlarmBloc>().add(
      AddOrUpdateAlarmEvent(
        alarm.copyWith(dayMask: alarm.dayMask & 0x7F),
        null,
      ),
    );
  }

  /// Silence for [Alarm.snoozeDurationMinutes], then ring again — up to the
  /// alarm's snooze allowance. Not a dismissal: the wake challenge still awaits.
  Future<void> _snooze(Alarm alarm) async {
    await _stopRing();
    _snoozesUsed++;
    if (!mounted) return;
    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(
      Duration(minutes: alarm.snoozeDurationMinutes),
      () => _startRing(alarm, fromSnooze: true),
    );
    // Surface any coincident, not-yet-fired alarm now rather than letting it be
    // lost while this one is snoozed; otherwise fall back to the idle face.
    _ringNextCoincidentOrClear(alarm);
  }

  bool _canSnooze(Alarm alarm) =>
      alarm.snoozeEnabled &&
      alarm.snoozeMaxCount > 0 &&
      _snoozesUsed < alarm.snoozeMaxCount;

  @override
  Widget build(BuildContext context) {
    final is24Hour = context.select<SettingsBloc, bool>(
      (b) => b.state.is24HourTime,
    );
    final alarms = context.select<AlarmBloc, List<Alarm>>(
      (b) => b.state.alarms,
    );

    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: _ringing != null
              ? _RingOverlay(
                  alarm: _ringing!,
                  is24Hour: is24Hour,
                  onDismiss: () => _handleDismiss(_ringing!),
                  onSnooze: _canSnooze(_ringing!)
                      ? () => _snooze(_ringing!)
                      : null,
                )
              : _ClockFace(
                  now: _now,
                  is24Hour: is24Hour,
                  nextAlarm: _nextAlarm(alarms, _now),
                  onExit: _confirmExit,
                ),
        ),
      ),
    );
  }

  Future<void> _confirmExit() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit dedicated clock mode?'),
        content: const Text(
          'This device will stop acting as a WakeGuard clock and return to the '
          'normal app. Your alarms and settings are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (leave == true) widget.onExit?.call();
  }

  /// The soonest upcoming enabled alarm, or null if none are enabled.
  ({Alarm alarm, DateTime at})? _nextAlarm(List<Alarm> alarms, DateTime from) {
    ({Alarm alarm, DateTime at})? best;
    for (final alarm in alarms) {
      if (!alarm.isActive) continue;
      final at = _nextOccurrence(alarm, from);
      if (best == null || at.isBefore(best.at)) {
        best = (alarm: alarm, at: at);
      }
    }
    return best;
  }

  /// Next wall-clock time [alarm] will sound at or after [from].
  DateTime _nextOccurrence(Alarm alarm, DateTime from) {
    final baseToday = DateTime(
      from.year,
      from.month,
      from.day,
      alarm.hour,
      alarm.minute,
    );
    if (!_hasRepeatDays(alarm)) {
      // One-time: today if still ahead, otherwise tomorrow.
      return baseToday.isAfter(from)
          ? baseToday
          : baseToday.add(const Duration(days: 1));
    }
    // Repeat: scan up to a week out for the next active weekday.
    for (var offset = 0; offset < 8; offset++) {
      final day = baseToday.add(Duration(days: offset));
      if (alarm.isDayActive(day.weekday % 7) &&
          (offset > 0 || day.isAfter(from))) {
        return day;
      }
    }
    return baseToday; // unreachable for an active repeat alarm
  }
}

/// The idle bedside face: Beta pill + exit, big centred time, date, next alarm,
/// and an honest one-line status about the mode's limits.
class _ClockFace extends StatelessWidget {
  final DateTime now;
  final bool is24Hour;
  final ({Alarm alarm, DateTime at})? nextAlarm;
  final VoidCallback onExit;

  const _ClockFace({
    required this.now,
    required this.is24Hour,
    required this.nextAlarm,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = nextAlarm;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        children: [
          Row(
            children: [
              const WakeStatusPill(
                label: 'Dedicated Clock · Beta',
                icon: Icons.nightlight_round,
                color: AppColors.warning,
              ),
              const Spacer(),
              IconButton(
                onPressed: onExit,
                icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant),
                tooltip: 'Exit dedicated clock mode',
              ),
            ],
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AlarmTimeUtils.formatTime(
                      now.hour,
                      now.minute,
                      is24Hour: is24Hour,
                    ),
                    style: TextStyle(
                      fontSize: 84,
                      fontWeight: FontWeight.w300,
                      letterSpacing: -1,
                      height: 1,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _dateLabel(now),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 26),
                  _NextAlarmPill(next: next, is24Hour: is24Hour, now: now),
                ],
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 14,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Keep this device plugged in and the app open. Best-effort — '
                  'the hardware WakeGuard clock is the tamper-proof one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String _dateLabel(DateTime d) =>
      '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
}

class _NextAlarmPill extends StatelessWidget {
  final ({Alarm alarm, DateTime at})? next;
  final bool is24Hour;
  final DateTime now;

  const _NextAlarmPill({
    required this.next,
    required this.is24Hour,
    required this.now,
  });

  @override
  Widget build(BuildContext context) {
    final n = next;
    if (n == null) {
      return const WakeStatusPill(
        label: 'No alarms set',
        icon: Icons.alarm_off_rounded,
        color: AppColors.warning,
      );
    }
    return WakeStatusPill(
      label: 'Next · ${AlarmTimeUtils.formatNextOccurrence(n.at, now)}',
      icon: Icons.alarm_rounded,
      color: Theme.of(context).colorScheme.primary,
    );
  }
}

/// Full-screen ring state: an urgent tint, the alarm identity, and the shared
/// task-aware dismissal button. Deliberately offers no free "dismiss anyway".
class _RingOverlay extends StatelessWidget {
  final Alarm alarm;
  final bool is24Hour;
  final VoidCallback onDismiss;

  /// Non-null only when the alarm allows another snooze; hides the button once
  /// the allowance is spent.
  final VoidCallback? onSnooze;

  const _RingOverlay({
    required this.alarm,
    required this.is24Hour,
    required this.onDismiss,
    this.onSnooze,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          const WakeStatusPill(
            label: 'Ringing now',
            icon: Icons.notifications_active_rounded,
            color: AppColors.error,
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.alarm_rounded, size: 64, color: AppColors.error),
                  const SizedBox(height: 18),
                  Text(
                    alarm.displayName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AlarmTimeUtils.formatTime(
                      alarm.hour,
                      alarm.minute,
                      is24Hour: is24Hour,
                    ),
                    style: TextStyle(
                      fontSize: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    RingingDismissal.instruction(alarm),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          WakePrimaryButton(
            label: RingingDismissal.actionLabel(alarm),
            icon: RingingDismissal.actionIcon(alarm),
            color: AppColors.error,
            onPressed: onDismiss,
          ),
          if (onSnooze != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: WakeSecondaryButton(
                label: 'Snooze ${alarm.snoozeDurationMinutes} min',
                icon: Icons.snooze_rounded,
                onPressed: onSnooze,
              ),
            ),
        ],
      ),
    );
  }
}
