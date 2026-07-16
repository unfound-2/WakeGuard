import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:smart_ble_alarm/core/platform/android_alarm_channel.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/utils/alarm_time_utils.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/widgets/ringing_dismissal.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';

/// Full-bleed, system-clock-style alarm surface shown on Android whenever an
/// alarm is ringing. It fills the whole screen (above the tab bar), appears over
/// the lock screen and turns the display on via [AndroidAlarmChannel], and can
/// only be left by completing the alarm's dismissal — the same task-aware
/// [RingingDismissal] every other surface uses, so the wake challenge (QR/photo)
/// is still fully enforced. Back is blocked (`PopScope`) so the alarm can't be
/// swiped away; the two shortcuts (Phone, Messages) let a call/text through
/// without stopping the ring.
///
/// Best-effort scope: a normally-installed Android app can't truly *block* other
/// apps (that needs Device Owner / kiosk mode), so this makes the alarm
/// impossible to dismiss without the challenge and trivially reachable for
/// calls/texts, rather than hard-jailing the launcher.
class FullScreenAlarmScreen extends StatefulWidget {
  final Alarm alarm;

  const FullScreenAlarmScreen({super.key, required this.alarm});

  @override
  State<FullScreenAlarmScreen> createState() => _FullScreenAlarmScreenState();
}

class _FullScreenAlarmScreenState extends State<FullScreenAlarmScreen> {
  Timer? _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Show over the keyguard, wake the screen, and keep it awake while ringing.
    AndroidAlarmChannel.armLockScreen();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    AndroidAlarmChannel.disarmLockScreen();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final is24Hour = context.select<SettingsBloc, bool>(
      (b) => b.state.is24HourTime,
    );
    final nowStr = AlarmTimeUtils.formatTime(
      _now.hour,
      _now.minute,
      is24Hour: is24Hour,
    );

    return PopScope(
      // Block Back so the alarm can't be swiped away without dismissing.
      canPop: false,
      child: Material(
        color: const Color(0xFF0E1116),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.primaryOrange,
                  size: 44,
                ),
                const SizedBox(height: 20),
                Text(
                  nowStr,
                  style: const TextStyle(
                    fontSize: 76,
                    height: 1.0,
                    fontWeight: FontWeight.w200,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.alarm.displayName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.92),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  RingingDismissal.instruction(widget.alarm),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
                const Spacer(flex: 3),
                // Dismiss / wake challenge — the only way to stop the ring.
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () =>
                        RingingDismissal.trigger(context, widget.alarm),
                    icon: Icon(RingingDismissal.actionIcon(widget.alarm)),
                    label: Text(
                      RingingDismissal.actionLabel(widget.alarm),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _ShortcutButton(
                        icon: Icons.phone_rounded,
                        label: 'Phone',
                        onTap: AndroidAlarmChannel.openDialer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _ShortcutButton(
                        icon: Icons.chat_bubble_rounded,
                        label: 'Messages',
                        onTap: AndroidAlarmChannel.openMessages,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShortcutButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ShortcutButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.24)),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      onPressed: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
