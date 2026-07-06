import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/wake_widgets.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../data/datasources/secure_key_datasource.dart';
import '../../../domain/entities/alarm.dart';
import '../../../domain/usecases/print_qr_code.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../alarm_edit_screen.dart';
import '../item_scan_screen.dart';
import '../scanner_screen.dart';

/// The Alarms tab, ported from the native WakeGuard AlarmsView: the alarm
/// list (AlarmRow-style cards) followed by a live "Timers" section
/// (TimerRow-style cards) merged into a single scrollable screen.
class AlarmsTab extends StatelessWidget {
  const AlarmsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
              children: [
                Text(
                  'Alarms',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Schedules sync to the physical clock when connected.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                _buildAlarmsList(),
                const SizedBox(height: 24),
                const WakeSection(
                  title: 'Timers',
                  subtitle:
                      'The clock runs timers on its own; these are live '
                      'mirrors.',
                  child: _TimersSection(),
                ),
              ],
            ),
            // The floating tab bar occupies the bottom edge, so the FAB sits
            // above it instead of using the Scaffold slot.
            Positioned(
              right: 20,
              bottom: 120,
              child: FloatingActionButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AlarmEditScreen()),
                  );
                },
                backgroundColor: Theme.of(context).colorScheme.primary,
                child: Icon(
                  Icons.add,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlarmsList() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return BlocBuilder<AlarmBloc, AlarmState>(
          builder: (context, state) {
            if (state.alarms.isEmpty) {
              return const WakeEmptyState(
                title: 'No alarms yet',
                message:
                    'Create your first WakeGuard alarm and choose whether a '
                    'wake challenge is required.',
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
  /// enable switch, a row of status pills, then a text-button action row.
  Widget _buildAlarmCard(
    BuildContext context,
    Alarm alarm,
    AlarmSyncStatus syncStatus,
    bool is24Hour,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final nextOccurrence = AlarmTimeUtils.nextOccurrence(alarm);

    return GestureDetector(
      onTap: () => _openEditor(context, alarm),
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: alarm.isActive
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alarm.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: alarm.isActive,
                  onChanged: (val) {
                    final updatedMask = val
                        ? (alarm.dayMask | 0x80)
                        : (alarm.dayMask & 0x7F);
                    context.read<AlarmBloc>().add(
                      AddOrUpdateAlarmEvent(
                        alarm.copyWith(dayMask: updatedMask),
                        _connectedDevice(context),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                WakeStatusPill(
                  label: AlarmTimeUtils.formatDays(alarm.dayMask),
                  icon: Icons.repeat_rounded,
                  color: scheme.onSurfaceVariant,
                ),
                if (nextOccurrence != null)
                  WakeStatusPill(
                    label: AlarmTimeUtils.formatNextOccurrence(
                      nextOccurrence,
                      DateTime.now(),
                    ),
                    icon: Icons.event_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
                if (alarm.qrRequired)
                  WakeStatusPill(
                    label: 'Challenge',
                    icon: Icons.center_focus_strong_rounded,
                    color: scheme.primary,
                  ),
                _syncPill(context, syncStatus),
                if (alarm.snoozeEnabled)
                  WakeStatusPill(
                    label: alarm.snoozeMaxCount > 0
                        ? 'Snooze ×${alarm.snoozeMaxCount}'
                        : 'Snooze on',
                    icon: Icons.snooze_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 2,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _actionButton(
                  context,
                  'Edit',
                  () => _openEditor(context, alarm),
                ),
                _actionButton(
                  context,
                  'Duplicate',
                  () => _duplicateAlarm(context, alarm),
                ),
                if (alarm.qrRequired && !alarm.usesItemScan)
                  _actionButton(
                    context,
                    'Print Code',
                    () => _printCode(context, alarm),
                  ),
                _actionButton(
                  context,
                  'Delete',
                  () => _deleteWithUndo(context, alarm),
                  color: scheme.error,
                ),
                if (alarm.qrRequired) _dismissButton(context, alarm),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Whether the alarm's settings are live on the clock. With on-demand BLE
  /// the phone is often disconnected while alarms are edited, so this tells
  /// the user at a glance which alarms the hardware will really ring versus
  /// which are still waiting to upload. Amber (pending) reads as "attention,
  /// not error" — the change is safely saved, just not on the hardware yet.
  WakeStatusPill _syncPill(BuildContext context, AlarmSyncStatus status) {
    final (Color color, IconData icon, String label) = switch (status) {
      AlarmSyncStatus.synced => (
        AppColors.success,
        Icons.check_circle_rounded,
        'On clock',
      ),
      AlarmSyncStatus.pending => (
        AppColors.warning,
        Icons.sync_rounded,
        'Pending sync',
      ),
      AlarmSyncStatus.failed => (
        Theme.of(context).colorScheme.error,
        Icons.error_rounded,
        'Sync failed',
      ),
    };
    return WakeStatusPill(label: label, icon: icon, color: color);
  }

  Widget _actionButton(
    BuildContext context,
    String label,
    VoidCallback onPressed, {
    Color? color,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color ?? Theme.of(context).colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }

  /// The dismissal entry point for challenge-protected alarms: item-scan
  /// alarms open the item camera, QR alarms open the code scanner.
  Widget _dismissButton(BuildContext context, Alarm alarm) {
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => alarm.usesItemScan
                ? ItemScanScreen(alarm: alarm)
                : ScannerScreen(alarmId: alarm.id),
          ),
        );
      },
      icon: Icon(
        alarm.usesItemScan
            ? Icons.center_focus_strong
            : Icons.qr_code_scanner,
        size: 16,
      ),
      label: Text(
        alarm.usesItemScan ? 'Scan Item' : 'Dismiss',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: scheme.error,
        backgroundColor: scheme.error.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  void _openEditor(BuildContext context, Alarm alarm) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlarmEditScreen(alarm: alarm)),
    );
  }

  Future<void> _printCode(BuildContext context, Alarm alarm) async {
    final usecase = PrintQrCodeUseCase(
      secureKeyDatasource: SecureKeyDatasource(),
    );
    try {
      await usecase.execute(alarm.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to open the print dialog.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  BluetoothDevice? _connectedDevice(BuildContext context) {
    final bleState = context.read<BleConnectionBloc>().state;
    return bleState is BleConnected ? bleState.device : null;
  }

  void _duplicateAlarm(BuildContext context, Alarm alarm) {
    final alarmBloc = context.read<AlarmBloc>();
    if (alarmBloc.state.alarms.length >= AlarmBloc.maxHardwareAlarms) {
      _showError(
        context,
        'The clock supports up to 5 alarms. Delete one before duplicating.',
      );
      return;
    }

    final duplicate = alarm.copyWith(id: _nextAlarmId(alarmBloc.state.alarms));
    // A duplicate is a new alarm with a new id → give it its own dismissal key.
    alarmBloc.add(
      AddOrUpdateAlarmEvent(
        duplicate,
        _connectedDevice(context),
        rotateSecureKey: true,
      ),
    );
  }

  void _deleteWithUndo(BuildContext context, Alarm alarm) {
    HapticFeedback.mediumImpact();
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

  int _nextAlarmId(List<Alarm> alarms) {
    final usedIds = alarms.map((alarm) => alarm.id).toSet();
    for (var id = 1; id <= 255; id++) {
      if (!usedIds.contains(id)) return id;
    }
    throw StateError('No alarm identifiers are available.');
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

/// Live view of app-side timer mirrors, rendered below the alarm list.
/// Rebuilds every second so countdowns tick, and lets the user clear finished
/// (or unwanted) timers from the list.
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
          return const WakeEmptyState(
            title: 'No timers running',
            message: 'Start one from the Home tab quick actions.',
            icon: Icons.timer_outlined,
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

  Widget _buildTimerCard(BuildContext context, CountdownTimer timer, DateTime now) {
    final done = timer.isDone(now);
    final remaining = timer.remaining(now);
    final primary = Theme.of(context).colorScheme.primary;
    final error = Theme.of(context).colorScheme.error;
    final accent = done ? error : primary;
    final progress = timer.totalSeconds <= 0
        ? 0.0
        : (remaining.inSeconds / timer.totalSeconds).clamp(0.0, 1.0);

    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      tintColor: done ? error : null,
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
            tooltip: done ? 'Dismiss' : 'Clear',
            icon: Icon(Icons.close_rounded, color: accent),
            onPressed: () {
              HapticFeedback.selectionClick();
              context.read<CountdownTimerCubit>().removeTimer(timer.id);
            },
          ),
        ],
      ),
    );
  }
}
