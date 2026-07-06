import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/entities/alarm.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../alarm_edit_screen.dart';
import '../scanner_screen.dart';
import '../item_scan_screen.dart';
import '../../../domain/usecases/print_qr_code.dart';
import '../../../data/datasources/secure_key_datasource.dart';

class AlarmsTab extends StatelessWidget {
  const AlarmsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: GlassBackground(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Alarms',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: TabBar(
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: 'ALARMS'),
                    Tab(text: 'TIMERS'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [_buildAlarmsList(), _buildTimersList(context)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimersList(BuildContext context) {
    return const _TimersList();
  }

  Widget _buildAlarmsList() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return BlocBuilder<AlarmBloc, AlarmState>(
          builder: (context, state) {
            if (state.alarms.isEmpty) {
              return _EmptyState(
                icon: Icons.alarm_add_rounded,
                title: 'No alarms yet',
                message:
                    'Create your first alarm and the clock will keep ringing '
                    'until you get up and complete the dismissal task.',
                actionLabel: 'Create alarm',
                onAction: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AlarmEditScreen()),
                  );
                },
              );
            }

            return Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.all(16).copyWith(bottom: 100),
                  itemCount: state.alarms.length,
                  itemBuilder: (context, index) {
                    final alarm = state.alarms[index];
                    final nextOccurrence = AlarmTimeUtils.nextOccurrence(alarm);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlarmEditScreen(alarm: alarm),
                            ),
                          );
                        },
                        child: GlassCard(
                          padding: const EdgeInsets.all(20),
                          borderRadius: 22,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (alarm.label != null &&
                                        alarm.label!.trim().isNotEmpty) ...[
                                      Text(
                                        alarm.label!.trim(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                    ],
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        AlarmTimeUtils.formatTime(
                                          alarm.hour,
                                          alarm.minute,
                                          is24Hour: settingsState.is24HourTime,
                                        ),
                                        maxLines: 1,
                                        style: TextStyle(
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                          letterSpacing: 1,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      AlarmTimeUtils.formatDays(
                                        alarm.dayMask,
                                      ).toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    if (nextOccurrence != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Next: ${AlarmTimeUtils.formatNextOccurrence(nextOccurrence, DateTime.now())}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    if (alarm.snoozeEnabled) ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.snooze_rounded,
                                            size: 14,
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            alarm.snoozeMaxCount > 0
                                                ? 'Snooze ×${alarm.snoozeMaxCount}'
                                                : 'Snooze on',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (alarm.qrRequired) ...[
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          if (!alarm.usesItemScan)
                                            OutlinedButton.icon(
                                              icon: Icon(
                                                Icons.print,
                                                size: 16,
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                              ),
                                              label: Text(
                                                'Print QR',
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.primary,
                                                ),
                                              ),
                                              style: OutlinedButton.styleFrom(
                                                side: BorderSide(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.5),
                                                ),
                                              ),
                                              onPressed: () async {
                                                final usecase =
                                                    PrintQrCodeUseCase(
                                                      secureKeyDatasource:
                                                          SecureKeyDatasource(),
                                                    );
                                                try {
                                                  await usecase.execute(
                                                    alarm.id,
                                                  );
                                                } catch (_) {
                                                  if (!context.mounted) return;
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: const Text(
                                                        'Unable to open the print dialog.',
                                                      ),
                                                      backgroundColor: Theme.of(
                                                        context,
                                                      ).colorScheme.error,
                                                    ),
                                                  );
                                                }
                                              },
                                            ),
                                          ElevatedButton.icon(
                                            icon: Icon(
                                              alarm.usesItemScan
                                                  ? Icons.center_focus_strong
                                                  : Icons.qr_code_scanner,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            label: Text(
                                              alarm.usesItemScan
                                                  ? 'Scan Item'
                                                  : 'Dismiss',
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                            onPressed: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      alarm.usesItemScan
                                                      ? ItemScanScreen(
                                                          alarm: alarm,
                                                        )
                                                      : ScannerScreen(
                                                          alarmId: alarm.id,
                                                        ),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                children: [
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
                                  PopupMenuButton<String>(
                                    tooltip: 'Alarm actions',
                                    icon: Icon(
                                      Icons.more_vert,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface,
                                    ),
                                    onSelected: (value) {
                                      if (value == 'duplicate') {
                                        _duplicateAlarm(context, alarm);
                                      } else if (value == 'delete') {
                                        _deleteWithUndo(context, alarm);
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(
                                        value: 'duplicate',
                                        child: Text('Duplicate'),
                                      ),
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('Delete'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AlarmEditScreen(),
                        ),
                      );
                    },
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
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

/// Live view of app-side timer mirrors. Rebuilds every second so countdowns
/// tick, and lets the user clear finished (or unwanted) timers from the list.
class _TimersList extends StatefulWidget {
  const _TimersList();

  @override
  State<_TimersList> createState() => _TimersListState();
}

class _TimersListState extends State<_TimersList> {
  Timer? _ticker;

  // Runs the 1-second countdown ticker only while at least one timer exists.
  // With an empty list this costs nothing — important because the Alarms tab
  // stays mounted in the IndexedStack even while another tab is on screen.
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
          return const _EmptyState(
            icon: Icons.timer_outlined,
            title: 'No active timers',
            message:
                'Start a timer from the Dashboard and its countdown will '
                'appear here while the clock runs it.',
          );
        }

        final now = DateTime.now();
        return ListView.builder(
          padding: const EdgeInsets.all(16).copyWith(bottom: 100),
          itemCount: timers.length,
          itemBuilder: (context, index) {
            final timer = timers[index];
            final done = timer.isDone(now);
            final remaining = timer.remaining(now);
            final primary = Theme.of(context).colorScheme.primary;
            final error = Theme.of(context).colorScheme.error;
            final accent = done ? error : primary;
            final progress = timer.totalSeconds <= 0
                ? 0.0
                : (remaining.inSeconds / timer.totalSeconds).clamp(0.0, 1.0);

            return Padding(
              padding: const EdgeInsets.only(bottom: 16.0),
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                borderRadius: 22,
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
                              fontWeight: FontWeight.w700,
                              color: Theme.of(context).colorScheme.onSurface,
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
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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
                        context.read<CountdownTimerCubit>().removeTimer(
                          timer.id,
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Friendly empty-state panel shared by the Alarms and Timers tabs.
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    primary.withValues(alpha: 0.24),
                    primary.withValues(alpha: 0.04),
                  ],
                ),
                border: Border.all(color: primary.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 44, color: primary),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
