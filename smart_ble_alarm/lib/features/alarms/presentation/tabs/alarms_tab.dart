import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/core/ui/wake_haptics.dart';
import 'package:smart_ble_alarm/core/utils/alarm_time_utils.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_state.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:smart_ble_alarm/features/timers/presentation/cubit/countdown_timer_cubit.dart';
import 'package:smart_ble_alarm/features/timers/presentation/widgets/create_timer_sheet.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/widgets/ringing_dismissal.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/screens/alarm_edit_screen.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/screens/alarm_templates_screen.dart';

/// The Alarms tab, ported from the native WakeGuard AlarmsView. A sliding
/// segmented control at the top splits the screen into two subtabs: "Alarm"
/// (the AlarmRow-style schedule list) and "Timer" (live TimerRow-style
/// mirrors). Only one subtab is on screen at a time.
class AlarmsTab extends StatefulWidget {
  const AlarmsTab({super.key});

  @override
  State<AlarmsTab> createState() => _AlarmsTabState();
}

class _AlarmsTabState extends State<AlarmsTab> {
  // 0 = Alarm subtab, 1 = Timer subtab.
  int _segment = 0;

  @override
  Widget build(BuildContext context) {
    final isAlarms = _segment == 0;
    final title = isAlarms ? 'Alarms' : 'Timers';
    return GlassBackground(
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 188),
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSegmentedControl(context),
                const SizedBox(height: 18),
                _ModeIntroCard(isAlarms: isAlarms),
                if (isAlarms) ...[
                  const SizedBox(height: 18),
                  _buildAlarmsList(),
                ] else ...[
                  const SizedBox(height: 18),
                  const _TimersSection(),
                ],
              ],
            ),
            Positioned(
              right: 20,
              bottom: 108,
              child: _CreateFab(
                // A single circular "+" that opens the create menu on the Alarm
                // subtab (New Alarm / Templates) or jumps straight to the timer
                // sheet on the Timer subtab, where there are no templates.
                onPressed: () => isAlarms
                    ? _showCreateMenu(context)
                    : _showCreateTimer(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The Alarm | Timer subtab switcher, styled to match the AM/PM control on
  /// the alarm editor (sliding thumb in the accent colour over a faint track).
  Widget _buildSegmentedControl(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final primary = Theme.of(context).colorScheme.primary;
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, alarmState) {
        return BlocBuilder<CountdownTimerCubit, List<CountdownTimer>>(
          builder: (context, timers) {
            return SizedBox(
              width: double.infinity,
              child: CupertinoSlidingSegmentedControl<int>(
                groupValue: _segment,
                backgroundColor: onSurface.withValues(alpha: 0.06),
                thumbColor: primary,
                children: {
                  0: _segmentLabel(
                    'Alarms ${alarmState.alarms.length}',
                    Icons.alarm_rounded,
                    selected: _segment == 0,
                    onSurface: onSurface,
                  ),
                  1: _segmentLabel(
                    'Timers ${timers.length}',
                    Icons.timer_rounded,
                    selected: _segment == 1,
                    onSurface: onSurface,
                  ),
                },
                onValueChanged: (value) {
                  if (value == null || value == _segment) return;
                  WakeHaptics.selectionClick();
                  setState(() => _segment = value);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _segmentLabel(
    String text,
    IconData icon, {
    required bool selected,
    required Color onSurface,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    final onAccent =
        ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
        ? Colors.white
        : Colors.black;
    final color = selected ? onAccent : onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmsList() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return BlocBuilder<AlarmBloc, AlarmState>(
          builder: (context, state) {
            if (state.alarms.isEmpty) {
              // No inline action button here: creating an alarm now lives on
              // the "+" button at the bottom right of the tab.
              return const _ActionEmptyState(
                title: 'No alarms scheduled',
                message:
                    'Create a protected wake plan with repeat days, '
                    'snooze, sound, and a wake challenge.',
                icon: Icons.alarm_rounded,
              );
            }

            return Column(
              children: [
                for (var i = 0; i < state.alarms.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _buildAlarmCard(
                    context,
                    state.alarms[i],
                    state.syncStatusFor(state.alarms[i]),
                    settingsState.is24HourTime,
                    state.ringingAlarmId == state.alarms[i].id,
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  /// One alarm in the native AlarmRow layout: big time + label with the
  /// enable switch and one compact status line. Swipe left to delete (with
  /// undo); tap to edit the secondary settings.
  Widget _buildAlarmCard(
    BuildContext context,
    Alarm alarm,
    AlarmSyncStatus syncStatus,
    bool is24Hour,
    bool isRinging,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final active = alarm.isActive;
    final statusColor = isRinging
        ? scheme.error
        : _syncStatusColor(context, syncStatus);
    final timeColor = isRinging
        ? scheme.error
        : (active ? scheme.onSurface : scheme.onSurfaceVariant);
    final summary = _alarmSummary(alarm, syncStatus);
    final repeatLabel = AlarmTimeUtils.formatDays(alarm.dayMask);
    final timeLabel = AlarmTimeUtils.formatTime(
      alarm.hour,
      alarm.minute,
      is24Hour: is24Hour,
    );

    return Dismissible(
      key: ValueKey('alarm-${alarm.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _deleteWithUndo(context, alarm),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 26),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(Icons.delete_rounded, color: Colors.white, size: 26),
      ),
      child: Semantics(
        button: true,
        label: 'Edit alarm, $timeLabel, ${alarm.displayName}',
        child: GestureDetector(
          onTap: () => _openEditor(context, alarm),
          child: GlassCard(
            blur:
                false, // list row: solid fill avoids per-frame blur while scrolling
            padding: const EdgeInsets.all(16),
            tintColor: isRinging ? scheme.error : null,
            borderColor: isRinging
                ? scheme.error
                : active
                ? scheme.primary.withValues(alpha: 0.36)
                : GlassTheme.of(context).stroke,
            borderWidth: isRinging ? 2 : 1,
            shadows: isRinging
                ? [
                    BoxShadow(
                      color: scheme.error.withValues(alpha: 0.24),
                      blurRadius: 24,
                      spreadRadius: -4,
                    ),
                  ]
                : wakeCardShadow(context),
            child: AnimatedOpacity(
              opacity: active || isRinging ? 1 : 0.56,
              duration: const Duration(milliseconds: 180),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        width: 6,
                        height: 56,
                        decoration: BoxDecoration(
                          color: statusColor,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                AlarmTimeUtils.formatTime(
                                  alarm.hour,
                                  alarm.minute,
                                  is24Hour: is24Hour,
                                ),
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w900,
                                  color: timeColor,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    alarm.displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: scheme.onSurfaceVariant.withValues(
                                    alpha: 0.62,
                                  ),
                                  size: 18,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (!isRinging)
                        Switch(
                          value: active,
                          onChanged: (val) =>
                              _setAlarmActive(context, alarm, val),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _StatusDot(color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          summary,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isRinging ? scheme.error : scheme.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _CompactStatusChip(
                          label: repeatLabel,
                          icon: Icons.repeat_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CompactStatusChip(
                          label: _challengeLabel(alarm),
                          icon: alarm.qrRequired
                              ? (alarm.usesItemScan
                                    ? Icons.camera_alt_rounded
                                    : Icons.qr_code_rounded)
                              : Icons.lock_open_rounded,
                          color: alarm.qrRequired
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (isRinging) ...[
                    const SizedBox(height: 14),
                    _InlineAlarmAction(
                      label: RingingDismissal.actionLabel(alarm),
                      icon: RingingDismissal.actionIcon(alarm),
                      color: scheme.error,
                      onPressed: () => RingingDismissal.trigger(context, alarm),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _syncStatusColor(BuildContext context, AlarmSyncStatus status) {
    return switch (status) {
      AlarmSyncStatus.synced => AppColors.success,
      AlarmSyncStatus.pending => AppColors.warning,
      AlarmSyncStatus.failed => Theme.of(context).colorScheme.error,
    };
  }

  String _syncStatusLabel(AlarmSyncStatus status) {
    return switch (status) {
      AlarmSyncStatus.synced => 'On clock',
      AlarmSyncStatus.pending => 'Pending sync',
      AlarmSyncStatus.failed => 'Sync failed',
    };
  }

  String _challengeLabel(Alarm alarm) {
    if (!alarm.qrRequired) return 'No challenge';
    if (alarm.usesItemScan) return 'Photo challenge';
    return 'QR challenge';
  }

  String _alarmSummary(Alarm alarm, AlarmSyncStatus status) {
    final parts = <String>[_syncStatusLabel(status), _challengeLabel(alarm)];
    return parts.join(' · ');
  }

  void _setAlarmActive(BuildContext context, Alarm alarm, bool active) {
    WakeHaptics.selectionClick();
    final updatedMask = active
        ? (alarm.dayMask | 0x80)
        : (alarm.dayMask & 0x7F);
    context.read<AlarmBloc>().add(
      AddOrUpdateAlarmEvent(
        alarm.copyWith(dayMask: updatedMask),
        _connectedDevice(context),
      ),
    );
  }

  void _openNewAlarm(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlarmEditScreen()),
    );
  }

  /// Opens the "+" create menu: a small glass sheet with New Alarm on top and
  /// Templates below it.
  void _showCreateMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: (sheetContext) => _CreateMenuSheet(
        onNewAlarm: () {
          Navigator.pop(sheetContext);
          _openNewAlarm(context);
        },
        onTemplates: () {
          Navigator.pop(sheetContext);
          _openTemplates(context);
        },
      ),
    );
  }

  void _openTemplates(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AlarmTemplatesScreen()),
    );
  }

  void _openEditor(BuildContext context, Alarm alarm) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlarmEditScreen(alarm: alarm)),
    );
  }

  BluetoothDevice? _connectedDevice(BuildContext context) {
    final bleState = context.read<BleConnectionBloc>().state;
    return bleState is BleConnected ? bleState.device : null;
  }

  void _deleteWithUndo(BuildContext context, Alarm alarm) {
    WakeHaptics.mediumImpact();
    final alarmBloc = context.read<AlarmBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final is24Hour = context.read<SettingsBloc>().state.is24HourTime;
    final timeStr = AlarmTimeUtils.formatTime(
      alarm.hour,
      alarm.minute,
      is24Hour: is24Hour,
    );

    alarmBloc.add(DeleteAlarmEvent(alarm.id, _connectedDevice(context)));

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted $timeStr alarm'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            // Re-add the exact alarm we removed, re-syncing to the clock.
            alarmBloc.add(
              AddOrUpdateAlarmEvent(alarm, _connectedDevice(context)),
            );
          },
        ),
      ),
    );
  }

  /// Opens the glass timer-creation sheet (wheel picker styled like the alarm
  /// editor). On confirm the sheet sends the duration to the clock and mirrors
  /// it into the live timer list.
  void _showCreateTimer(BuildContext context) {
    showCreateTimerSheet(context);
  }
}

class _ModeIntroCard extends StatelessWidget {
  final bool isAlarms;

  const _ModeIntroCard({required this.isAlarms});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isAlarms ? scheme.primary : AppColors.success;
    final icon = isAlarms ? Icons.alarm_rounded : Icons.timer_rounded;
    final title = isAlarms ? 'Alarm schedules' : 'Live timers';
    final body = isAlarms
        ? 'Clean wake plans that sync to the clock when connected.'
        : 'Countdown mirrors for timers currently running on the clock.';
    final badge = isAlarms ? 'Clock sync' : 'Live mirror';

    return GlassCard(
      borderRadius: 24,
      padding: const EdgeInsets.all(16),
      tintColor: accent,
      borderColor: accent.withValues(alpha: 0.38),
      shadows: wakeCardShadow(context),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: accent.withValues(alpha: 0.28)),
            ),
            child: Icon(icon, color: accent, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _SmallBadge(label: badge, color: accent),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    height: 1.28,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionEmptyState extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  // Optional call-to-action. When omitted (e.g. the Alarms empty state, whose
  // create action now lives on the "+" button), only the title and message show.
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback? onAction;

  const _ActionEmptyState({
    required this.title,
    required this.message,
    required this.icon,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassTheme.of(context);

    return GlassCard(
      borderRadius: 26,
      padding: const EdgeInsets.all(22),
      shadows: wakeCardShadow(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: glass.stroke),
              ),
              child: Icon(icon, color: scheme.primary, size: 28),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.08,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.36,
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 20),
            _InlineAlarmAction(
              label: actionLabel!,
              icon: actionIcon!,
              color: scheme.primary,
              onPressed: onAction!,
            ),
          ],
        ],
      ),
    );
  }
}

/// The circular "+" floating action button anchored to the bottom-right of the
/// Alarms tab. Replaces the old full-width action bar.
class _CreateFab extends StatelessWidget {
  final VoidCallback onPressed;

  const _CreateFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = GlassTheme.of(context);
    final dark = glass.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: 'Add',
      child: Material(
        color: scheme.primary.withValues(alpha: dark ? 0.94 : 1),
        shape: const CircleBorder(),
        elevation: 0,
        shadowColor: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            WakeHaptics.lightImpact();
            onPressed();
          },
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.34),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.34),
                  blurRadius: 22,
                  spreadRadius: -6,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Icon(Icons.add_rounded, color: scheme.onPrimary, size: 30),
          ),
        ),
      ),
    );
  }
}

/// The glass sheet shown by the "+" button: New Alarm on top, Templates below,
/// with breathing room between them.
class _CreateMenuSheet extends StatelessWidget {
  final VoidCallback onNewAlarm;
  final VoidCallback onTemplates;

  const _CreateMenuSheet({required this.onNewAlarm, required this.onTemplates});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: GlassCard(
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          shadows: wakeCardShadow(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              WakePrimaryButton(
                label: 'New Alarm',
                icon: Icons.add_alarm_rounded,
                onPressed: onNewAlarm,
              ),
              const SizedBox(height: 12),
              WakeSecondaryButton(
                label: 'Templates',
                icon: Icons.dashboard_customize_rounded,
                onPressed: onTemplates,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactStatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _CompactStatusChip({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final dark = GlassTheme.of(context).brightness == Brightness.dark;
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: dark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineAlarmAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _InlineAlarmAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          WakeHaptics.mediumImpact();
          onPressed();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: scheme.onPrimary, size: 19),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SmallBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final Color color;

  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.32),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

/// Live view of app-side timer mirrors, shown on the Timer subtab. Rebuilds
/// every second so countdowns tick, and lets the user clear finished (or
/// unwanted) timers from the list.
class _TimersSection extends StatefulWidget {
  const _TimersSection();

  @override
  State<_TimersSection> createState() => _TimersSectionState();
}

class _TimersSectionState extends State<_TimersSection> {
  Timer? _ticker;

  // Runs the 1-second countdown ticker only while at least one timer exists.
  // With an empty list this costs nothing — important because the tab stays
  // mounted in the IndexedStack even while another tab is on screen.
  void _syncTicker(bool hasTimers) {
    if (hasTimers && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!hasTimers && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    two(int v) => v.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CountdownTimerCubit, List<CountdownTimer>>(
      builder: (context, timers) {
        // Start/stop the ticker in step with whether any timer is running.
        _syncTicker(timers.isNotEmpty);
        if (timers.isEmpty) {
          return _ActionEmptyState(
            title: 'No timers running',
            message:
                'Start a timer on the clock and keep a live countdown '
                'mirror here while it runs.',
            icon: Icons.timer_outlined,
            actionLabel: 'Start Timer',
            actionIcon: Icons.timer_rounded,
            onAction: () => showCreateTimerSheet(context),
          );
        }

        final now = DateTime.now();
        return Column(
          children: [
            for (var i = 0; i < timers.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              _buildTimerCard(context, timers[i], now),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTimerCard(
    BuildContext context,
    CountdownTimer timer,
    DateTime now,
  ) {
    final done = timer.isDone(now);
    final remaining = timer.remaining(now);
    final primary = Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;
    final accent = done ? error : primary;
    final progress = timer.totalSeconds <= 0
        ? 0.0
        : (remaining.inSeconds / timer.totalSeconds).clamp(0.0, 1.0);

    return GlassCard(
      blur:
          false, // live timer row (rebuilds every second): skip per-frame blur
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      tintColor: done ? error : primary,
      borderColor: accent.withValues(alpha: done ? 0.70 : 0.34),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            height: 52,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: done ? 1 : progress,
                  strokeWidth: 4,
                  backgroundColor: accent.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation(accent),
                ),
                Icon(
                  done
                      ? Icons.notifications_active_rounded
                      : Icons.timer_rounded,
                  size: 22,
                  color: accent,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  timer.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  done ? "Time's up" : _format(remaining),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: done
                        ? error
                        : Theme.of(context).colorScheme.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: done ? 'Stop timer' : 'Cancel timer',
            icon: Icon(
              done ? Icons.stop_rounded : Icons.close_rounded,
              color: accent,
            ),
            onPressed: () => _stopTimer(context, timer),
          ),
        ],
      ),
    );
  }

  /// Stops the timer on the clock (0x0B) and removes the local mirror. Sending
  /// the stop command is what actually silences a finished-timer chime or drops
  /// a still-running countdown on the hardware — previously the ✕ only cleared
  /// the app's list while the clock kept sounding until its 60s auto-timeout.
  Future<void> _stopTimer(BuildContext context, CountdownTimer timer) async {
    WakeHaptics.selectionClick();
    final cubit = context.read<CountdownTimerCubit>();
    final bleState = context.read<BleConnectionBloc>().state;
    if (bleState is BleConnected) {
      try {
        await context.read<BleRepository>().sendCommand(
          bleState.device,
          0x0B,
          const [],
        );
      } catch (_) {
        // Best-effort: still clear the mirror so the UI recovers even if the
        // write failed (the clock also self-silences after its timeout).
      }
    }
    cubit.removeTimer(timer.id);
  }
}
