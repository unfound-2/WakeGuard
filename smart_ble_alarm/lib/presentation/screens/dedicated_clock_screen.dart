import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
// Best-effort keep-screen-awake. Wrapped in try/catch everywhere so a missing
// platform implementation (e.g. in widget tests) can never crash the clock.
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/audio/alarm_sound.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/wake_widgets.dart';
import '../../core/utils/alarm_time_utils.dart';
import '../../domain/entities/alarm.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../widgets/ringing_dismissal.dart';

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

  /// Loops the synthesized alarm tone while ringing. Lazily created; all calls
  /// are best-effort so a missing audio platform impl never crashes the clock.
  AudioPlayer? _player;
  Timer? _volumeRamp; // drives the gradual-wake fade-in
  Timer? _snoozeTimer; // re-arms the ring after a snooze
  int _snoozesUsed = 0; // reset each fresh ring; gates the snooze button

  /// The alarm currently sounding on this device (drives the ring overlay). Null
  /// while the clock is idle. Local to this screen — there is no hardware clock
  /// pushing 0x08, so the dedicated clock owns its own ring state.
  Alarm? _ringing;

  /// Guards against re-firing the same alarm every tick within its minute. Keyed
  /// by alarm id + calendar minute so each occurrence rings exactly once.
  String? _lastFiredKey;

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
    _volumeRamp?.cancel();
    _snoozeTimer?.cancel();
    try {
      _player?.dispose();
    } catch (_) {}
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
    final alarms = context.read<AlarmBloc>().state.alarms;
    for (final alarm in alarms) {
      if (!alarm.isActive) continue;
      if (alarm.hour != now.hour || alarm.minute != now.minute) continue;
      // Repeat alarms fire only on their configured weekdays; a one-time alarm
      // (no repeat bits) fires at its time each day it stays enabled.
      if (_hasRepeatDays(alarm) && !alarm.isDayActive(now.weekday % 7)) continue;
      final key = '${alarm.id}-${now.year}-${now.month}-${now.day}'
          '-${now.hour}-${now.minute}';
      if (_lastFiredKey == key) continue;
      _lastFiredKey = key;
      _startRing(alarm);
      return;
    }
  }

  bool _hasRepeatDays(Alarm alarm) => (alarm.dayMask & 0x7F) != 0;

  void _startRing(Alarm alarm, {bool fromSnooze = false}) {
    if (!fromSnooze) _snoozesUsed = 0;
    setState(() => _ringing = alarm);
    HapticFeedback.heavyImpact();
    // Pulse the haptics alongside the looping tone as a stronger wake cue.
    _ringHaptic?.cancel();
    _ringHaptic = Timer.periodic(
      const Duration(milliseconds: 1400),
      (_) => HapticFeedback.heavyImpact(),
    );
    _startAudio(alarm);
  }

  /// Loop the synthesized alarm tone at the alarm's configured volume, ramping
  /// up over the gradual-wake window when set. All best-effort.
  Future<void> _startAudio(Alarm alarm) async {
    try {
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      // Ring through the iOS silent switch and route to the alarm stream on
      // Android. Guarded independently — an unsupported option must not stop the
      // tone from playing at all.
      try {
        await player.setAudioContext(
          AudioContext(
            iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: const {AVAudioSessionOptions.duckOthers},
            ),
            android: const AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: AndroidContentType.sonification,
              usageType: AndroidUsageType.alarm,
              audioFocus: AndroidAudioFocus.gain,
            ),
          ),
        );
      } catch (_) {}
      final target = (alarm.volumePercent.clamp(1, 100)) / 100.0;
      if (alarm.gradualWakeSeconds > 0) {
        final start = (target * 0.15).clamp(0.05, target);
        await player.setVolume(start);
        _rampVolume(start, target, alarm.gradualWakeSeconds);
      } else {
        await player.setVolume(target);
      }
      await player.play(BytesSource(buildAlarmToneWav()));
    } catch (_) {
      // Audio unavailable (e.g. tests/desktop) — the visual ring + haptics stand.
    }
  }

  void _rampVolume(double start, double target, int seconds) {
    _volumeRamp?.cancel();
    const stepMs = 500;
    final steps = (seconds * 1000 / stepMs).ceil().clamp(1, 600);
    var step = 0;
    _volumeRamp = Timer.periodic(const Duration(milliseconds: stepMs), (t) async {
      step++;
      final frac = (step / steps).clamp(0.0, 1.0);
      try {
        await _player?.setVolume(start + (target - start) * frac);
      } catch (_) {}
      if (frac >= 1.0) t.cancel();
    });
  }

  Future<void> _stopRing() async {
    _ringHaptic?.cancel();
    _volumeRamp?.cancel();
    try {
      await _player?.stop();
    } catch (_) {}
  }

  Future<void> _handleDismiss(Alarm alarm) async {
    // Stop the local tone, then reuse the exact task-aware dismissal the hardware
    // clock uses: no-task -> dismiss, item -> photo, QR -> scan. It clears the
    // shared ringing state and records history; we additionally clear the local
    // ring. (Foreground beta: backing out of a challenge silences this device —
    // the hardware clock is the tamper-proof enforcement.)
    _snoozeTimer?.cancel();
    await _stopRing();
    if (!mounted) return;
    await RingingDismissal.trigger(context, alarm);
    if (!mounted) return;
    setState(() => _ringing = null);
  }

  /// Silence for [Alarm.snoozeDurationMinutes], then ring again — up to the
  /// alarm's snooze allowance. Not a dismissal: the wake challenge still awaits.
  Future<void> _snooze(Alarm alarm) async {
    await _stopRing();
    _snoozesUsed++;
    if (!mounted) return;
    setState(() => _ringing = null);
    _snoozeTimer?.cancel();
    _snoozeTimer = Timer(
      Duration(minutes: alarm.snoozeDurationMinutes),
      () => _startRing(alarm, fromSnooze: true),
    );
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
                icon: Icon(
                  Icons.close_rounded,
                  color: scheme.onSurfaceVariant,
                ),
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
                  Icon(
                    Icons.alarm_rounded,
                    size: 64,
                    color: AppColors.error,
                  ),
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
