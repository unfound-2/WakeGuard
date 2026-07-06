import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ble/ble_payloads.dart';
import '../../../core/ble/clock_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/wake_widgets.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../domain/entities/alarm.dart';
import '../../../domain/repositories/ble_repository.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_event.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../alarm_edit_screen.dart';
import '../item_scan_screen.dart';
import '../scanner_screen.dart';

/// The Home dashboard, matching the native WakeGuard HomeView: live header,
/// connection overview, metric tiles, the next-alarm / ringing card, quick
/// actions, and recent activity — all on the shared liquid-glass system.
class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
  static const List<String> _months = [
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

  @override
  void initState() {
    super.initState();
    loadLastClockSync();
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            // The next-alarm card leads the dashboard; it carries its own
            // bottom spacing and collapses to nothing when no alarm is active.
            _PeriodicRebuild(
              interval: const Duration(seconds: 30),
              builder: (context) => _buildNextAlarm(context),
            ),
            _buildConnectionOverview(),
            const SizedBox(height: 24),
            _buildMetricsGrid(),
            const SizedBox(height: 24),
            _buildQuickActions(),
            const SizedBox(height: 24),
            _buildRecentActivity(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------

  String _dateTimeLine(bool is24Hour) {
    final now = DateTime.now();
    final time = AlarmTimeUtils.formatTime(
      now.hour,
      now.minute,
      is24Hour: is24Hour,
    );
    return '${_weekdays[now.weekday - 1]}, '
        '${_months[now.month - 1]} ${now.day} · $time';
  }

  Widget _buildHeader() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (prev, curr) => prev.is24HourTime != curr.is24HourTime,
      builder: (context, settings) {
        return Row(
          children: [
            const WakeLogoMark(size: 52),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PeriodicRebuild(
                    interval: const Duration(seconds: 15),
                    builder: (context) => Text(
                      _dateTimeLine(settings.is24HourTime),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your clock at a glance',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Connection overview
  // ---------------------------------------------------------------------

  Widget _buildConnectionOverview() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        final bool busy = bleState is BleConnecting || bleState is BleScanning;

        final String title;
        final String detail;
        final String pillLabel;
        final IconData pillIcon;
        final Color pillColor;
        if (bleState is BleConnected) {
          title = bleState.device.platformName.isEmpty
              ? 'WakeGuard Clock'
              : bleState.device.platformName;
          detail = 'The hardware link is active.';
          pillLabel = 'Connected';
          pillIcon = Icons.check_circle_rounded;
          pillColor = AppColors.success;
        } else if (busy) {
          title = 'WakeGuard Clock';
          detail = 'Re-establishing the link to your clock…';
          pillLabel = 'Connecting';
          pillIcon = Icons.sync_rounded;
          pillColor = Theme.of(context).colorScheme.primary;
        } else {
          title = 'Clock not connected';
          detail = 'Tap to connect to your remembered clock.';
          pillLabel = 'Disconnected';
          pillIcon = Icons.error_outline_rounded;
          pillColor = AppColors.warning;
        }

        final reconnectable = bleState is! BleConnected && !busy;

        // Reconnect on demand when disconnected; the clock keeps running
        // alarms on its own, so we don't hold the connection continuously.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: reconnectable
              ? () => context.read<BleConnectionBloc>().add(ReconnectEvent())
              : null,
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
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            detail,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    WakeStatusPill(
                      label: pillLabel,
                      icon: pillIcon,
                      color: pillColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Compact "N of M alarms synced" line inside the connection card, so the
  /// user can trust at a glance that the clock actually has their alarms — the
  /// app is usually disconnected (on-demand BLE), so "saved" and "live" can
  /// diverge.
  Widget _buildSyncSummary() {
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, state) {
        final total = state.alarms.length;
        if (total == 0) return const SizedBox.shrink();

        final synced = state.syncedAlarmCount;
        final failed = state.alarms
            .where((a) => state.syncStatusFor(a) == AlarmSyncStatus.failed)
            .length;
        final allSynced = synced == total;

        final Color color;
        final IconData icon;
        final String text;
        if (allSynced) {
          color = AppColors.success;
          icon = Icons.cloud_done_rounded;
          text = total == 1
              ? 'Alarm synced to clock'
              : 'All $total alarms synced';
        } else {
          color = failed > 0
              ? Theme.of(context).colorScheme.error
              : AppColors.warning;
          icon = failed > 0
              ? Icons.error_outline_rounded
              : Icons.cloud_upload_rounded;
          final pending = total - synced;
          text = failed > 0
              ? '$synced of $total synced · $failed failed'
              : '$synced of $total synced · $pending pending';
        }

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Metrics grid
  // ---------------------------------------------------------------------

  /// The soonest upcoming occurrence across all active alarms, or null.
  ({Alarm alarm, DateTime occurrence})? _nextAlarmEntry(
    AlarmState state,
    DateTime now,
  ) {
    final entries =
        state.alarms
            .where((a) => a.isActive)
            .map(
              (a) => (
                alarm: a,
                occurrence: AlarmTimeUtils.nextOccurrence(a, from: now),
              ),
            )
            .where((e) => e.occurrence != null)
            .map((e) => (alarm: e.alarm, occurrence: e.occurrence!))
            .toList()
          ..sort((a, b) => a.occurrence.compareTo(b.occurrence));
    if (entries.isEmpty) return null;
    return entries.first;
  }

  String _formatRemaining(Duration remaining) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Widget _buildMetricsGrid() {
    return _PeriodicRebuild(
      interval: const Duration(seconds: 30),
      builder: (context) {
        final now = DateTime.now();
        return GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          // Make tiles taller as text scales up so large accessibility font
          // sizes don't overflow the tile content.
          childAspectRatio:
              (1.25 / MediaQuery.textScalerOf(context).scale(1.0)).clamp(
                0.68,
                1.3,
              ),
          children: [
            BlocBuilder<BleConnectionBloc, BleState>(
              builder: (context, bleState) => WakeMetricTile(
                title: 'Device',
                value: bleState is BleConnected
                    ? (bleState.device.platformName.isEmpty
                          ? 'WakeGuard Clock'
                          : bleState.device.platformName)
                    : 'Not paired',
                icon: Icons.alarm_rounded,
              ),
            ),
            BlocBuilder<AlarmBloc, AlarmState>(
              builder: (context, alarmState) =>
                  BlocBuilder<SettingsBloc, SettingsState>(
                    buildWhen: (prev, curr) =>
                        prev.is24HourTime != curr.is24HourTime,
                    builder: (context, settings) {
                      final entry = _nextAlarmEntry(alarmState, now);
                      return WakeMetricTile(
                        title: 'Next Alarm',
                        value: entry == null
                            ? 'None'
                            : AlarmTimeUtils.formatTime(
                                entry.alarm.hour,
                                entry.alarm.minute,
                                is24Hour: settings.is24HourTime,
                              ),
                        icon: Icons.notifications_active_rounded,
                      );
                    },
                  ),
            ),
            BlocBuilder<CountdownTimerCubit, List<CountdownTimer>>(
              builder: (context, timers) {
                final running = timers.where((t) => !t.isDone(now)).toList()
                  ..sort((a, b) => a.endEpochMs.compareTo(b.endEpochMs));
                return WakeMetricTile(
                  title: 'Active Timer',
                  value: running.isEmpty
                      ? 'None'
                      : _formatRemaining(running.first.remaining(now)),
                  icon: Icons.timer_rounded,
                );
              },
            ),
            BlocBuilder<SettingsBloc, SettingsState>(
              buildWhen: (prev, curr) => prev.is24HourTime != curr.is24HourTime,
              builder: (context, settings) =>
                  ValueListenableBuilder<DateTime?>(
                    valueListenable: lastClockSync,
                    builder: (context, lastSync, _) => WakeMetricTile(
                      title: 'Last Sync',
                      value: lastSync == null
                          ? 'Never'
                          : AlarmTimeUtils.formatSyncTimestamp(
                              lastSync,
                              is24Hour: settings.is24HourTime,
                            ),
                      icon: Icons.history_rounded,
                    ),
                  ),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // Next alarm / ringing card
  // ---------------------------------------------------------------------

  Widget _buildNextAlarm(BuildContext context) {
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, alarmState) {
        final now = DateTime.now();
        final entry = _nextAlarmEntry(alarmState, now);
        if (entry == null) return const SizedBox.shrink();

        final activeNextAlarm = entry.alarm;
        final nextOccurrence = entry.occurrence;
        final isRinging = alarmState.ringingAlarmId == activeNextAlarm.id;

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final timeStr = AlarmTimeUtils.formatTime(
              activeNextAlarm.hour,
              activeNextAlarm.minute,
              is24Hour: settingsState.is24HourTime,
            );
            final primary = Theme.of(context).colorScheme.primary;
            final error = Theme.of(context).colorScheme.error;
            final usesItem = activeNextAlarm.usesItemScan;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: GlassCard(
                padding: const EdgeInsets.all(22),
                tintColor: isRinging ? error : primary,
                borderColor: isRinging
                    ? error
                    : primary.withValues(alpha: 0.4),
                borderWidth: isRinging ? 2 : 1,
                shadows: [
                  BoxShadow(
                    color: (isRinging ? error : primary).withValues(
                      alpha: 0.22,
                    ),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
                child: isRinging
                    ? Column(
                        children: [
                          Text(
                            'ALARM RINGING',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: error,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            timeStr,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            usesItem
                                ? 'Verify ${activeNextAlarm.itemLabel!} '
                                      'to dismiss.'
                                : 'Scan the printed backup code to dismiss.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: error,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              icon: Icon(
                                usesItem
                                    ? Icons.center_focus_strong_rounded
                                    : Icons.qr_code_scanner_rounded,
                                size: 26,
                              ),
                              label: Text(
                                usesItem
                                    ? 'VERIFY WAKE OBJECT'
                                    : 'SCAN BACKUP CODE',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              onPressed: () =>
                                  _pushDismissal(context, activeNextAlarm),
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'NEXT ALARM',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                timeStr,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 34,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                AlarmTimeUtils.formatNextOccurrence(
                                  nextOccurrence,
                                  now,
                                ),
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.alarm_on_rounded,
                              color: primary,
                              size: 34,
                            ),
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

  // ---------------------------------------------------------------------
  // Quick actions
  // ---------------------------------------------------------------------

  Widget _buildQuickActions() {
    return WakeSection(
      title: 'Quick Actions',
      child: GridView.count(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        // Make tiles taller as text scales up so large accessibility font
        // sizes don't overflow the tile content.
        childAspectRatio:
            (1.3 / MediaQuery.textScalerOf(context).scale(1.0)).clamp(
              0.66,
              1.32,
            ),
        children: [
          WakeQuickAction(
            title: 'Create Alarm',
            icon: Icons.add_alarm_rounded,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AlarmEditScreen()),
              );
            },
          ),
          WakeQuickAction(
            title: 'Start Timer',
            icon: Icons.timer_rounded,
            onTap: () => _showTimerDialog(context),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Recent activity
  // ---------------------------------------------------------------------

  Widget _buildRecentActivity() {
    return WakeSection(
      title: 'Recent Activity',
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        shadows: wakeCardShadow(context),
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueListenableBuilder<DateTime?>(
                  valueListenable: lastClockSync,
                  builder: (context, lastSync, _) => WakeActivityRow(
                    title: 'Synchronization',
                    subtitle: lastSync == null
                        ? 'No sync completed yet'
                        : AlarmTimeUtils.formatSyncTimestamp(
                            lastSync,
                            is24Hour: settingsState.is24HourTime,
                          ),
                    icon: Icons.sync_rounded,
                  ),
                ),
                _buildSyncSummary(),
                const SizedBox(height: 16),
                WakeSecondaryButton(
                  label: 'Sync Now',
                  icon: Icons.sync_rounded,
                  // Always enabled: when disconnected the flow explains why it
                  // can't sync instead of silently disabling the button.
                  onPressed: () => _syncNow(context),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Behaviors (unchanged flows)
  // ---------------------------------------------------------------------

  void _showTimerDialog(BuildContext context) {
    Duration selectedDuration = const Duration(minutes: 15);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: Text(
                'Start Timer',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
              content: SizedBox(
                width: 280,
                height: 200,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: Theme.of(context).brightness,
                    textTheme: CupertinoTextThemeData(
                      pickerTextStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hms,
                    initialTimerDuration: selectedDuration,
                    onTimerDurationChanged: (Duration newDuration) {
                      setState(() {
                        selectedDuration = newDuration;
                      });
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'CANCEL',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final bleState = context.read<BleConnectionBloc>().state;
                    if (bleState is BleConnected) {
                      final durationSeconds = selectedDuration.inSeconds;
                      if (durationSeconds <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Choose a timer duration first.',
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                        );
                        return;
                      }

                      try {
                        await context.read<BleRepository>().sendCommand(
                          bleState.device,
                          0x0A,
                          BlePayloads.uint32(durationSeconds),
                        );
                        if (!context.mounted) return;
                        context.read<CountdownTimerCubit>().startTimer(
                          selectedDuration,
                        );
                        HapticFeedback.mediumImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Timer started on clock!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } catch (_) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'Timer could not be sent to the clock.',
                            ),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                        );
                        return;
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Not connected to clock'),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(context);
                  },
                  child: Text(
                    'START',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _syncNow(BuildContext context) async {
    final bleState = context.read<BleConnectionBloc>().state;
    if (bleState is! BleConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Connect to the clock before syncing.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    await syncConnectedClock(context, bleState.device, showSuccess: true);
  }

  /// Routes to the correct dismissal flow for [alarm]: the item-recognition
  /// screen for item alarms, the QR scanner otherwise.
  void _pushDismissal(BuildContext context, Alarm alarm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => alarm.usesItemScan
            ? ItemScanScreen(alarm: alarm)
            : ScannerScreen(alarmId: alarm.id),
      ),
    );
  }

}

/// Rebuilds [builder] on a fixed [interval] so relative time labels (the live
/// header clock, the "next alarm in 7h 20m" countdown, timer tiles) stay
/// current without a full screen rebuild.
class _PeriodicRebuild extends StatefulWidget {
  final Duration interval;
  final WidgetBuilder builder;

  const _PeriodicRebuild({required this.interval, required this.builder});

  @override
  State<_PeriodicRebuild> createState() => _PeriodicRebuildState();
}

class _PeriodicRebuildState extends State<_PeriodicRebuild> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.interval, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
