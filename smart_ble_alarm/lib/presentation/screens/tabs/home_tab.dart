import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ble/clock_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/ui/app_snackbar.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/wake_widgets.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../domain/entities/alarm.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_event.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../../widgets/create_timer_sheet.dart';
import '../alarm_edit_screen.dart';
import '../../widgets/ringing_dismissal.dart';

/// The Home dashboard, matching the native WakeGuard HomeView: live header,
/// connection overview, metric tiles, the next-alarm / ringing card, quick
/// actions, and recent activity — all on the shared liquid-glass system.
class HomeTab extends StatefulWidget {
  /// Switches the app to the Alarms tab (wired from MainScreen). Lets the
  /// next-alarm and live-timer cards act as shortcuts into the Alarms screen.
  final VoidCallback? onOpenAlarms;

  const HomeTab({super.key, this.onOpenAlarms});

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
            // Live timers tick every second so the dashboard reflects them in
            // real time; collapses to nothing when no timer is running.
            _buildLiveTimers(),
            _buildConnectionStatus(),
            const SizedBox(height: 24),
            _buildQuickActions(),
            const SizedBox(height: 24),
            _buildDetails(),
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

  /// Compact one-line connection status. The clock name is intentionally not a
  /// big titled box here — it lives in the Details row at the bottom — so this
  /// only conveys link state and offers a tap-to-reconnect when down.
  Widget _buildConnectionStatus() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        final scheme = Theme.of(context).colorScheme;
        final busy = bleState is BleConnecting || bleState is BleScanning;

        final IconData icon;
        final Color color;
        final String label;
        final bool reconnectable;
        if (bleState is BleConnected) {
          icon = Icons.bluetooth_connected_rounded;
          color = AppColors.success;
          label = 'Connected to your clock';
          reconnectable = false;
        } else if (busy) {
          icon = Icons.bluetooth_searching_rounded;
          color = scheme.primary;
          label = 'Reconnecting to your clock…';
          reconnectable = false;
        } else {
          icon = Icons.bluetooth_disabled_rounded;
          color = AppColors.warning;
          label = 'Not connected · tap to reconnect';
          reconnectable = true;
        }

        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shadows: wakeCardShadow(context),
          onTap: reconnectable
              ? () => context.read<BleConnectionBloc>().add(ReconnectEvent())
              : null,
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                )
              else if (reconnectable)
                Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
        );
      },
    );
  }

  /// Live-ticking summary of the soonest running timer (updates every second),
  /// so the Home dashboard reflects timers in real time. Tapping it opens the
  /// Alarms tab where the full timer list lives. Hidden when no timer runs.
  Widget _buildLiveTimers() {
    return BlocBuilder<CountdownTimerCubit, List<CountdownTimer>>(
      builder: (context, timers) {
        if (timers.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: _PeriodicRebuild(
            interval: const Duration(seconds: 1),
            builder: (context) {
              final now = DateTime.now();
              final scheme = Theme.of(context).colorScheme;
              final sorted = [...timers]
                ..sort((a, b) => a.endEpochMs.compareTo(b.endEpochMs));
              final soonest = sorted.first;
              final done = soonest.isDone(now);
              final accent = done ? scheme.error : scheme.primary;
              final others = timers.length - 1;
              return GlassCard(
                padding: const EdgeInsets.all(18),
                shadows: wakeCardShadow(context),
                tintColor: done ? scheme.error : null,
                onTap: widget.onOpenAlarms,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        done
                            ? Icons.notifications_active_rounded
                            : Icons.timer_rounded,
                        color: accent,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            others > 0
                                ? '${soonest.label} · +$others more'
                                : soonest.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            done ? "Time's up" : _formatRemaining(
                              soonest.remaining(now),
                            ),
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: done ? scheme.error : scheme.onSurface,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              );
            },
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

        return Row(
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

  // ---------------------------------------------------------------------
  // Next alarm / ringing card
  // ---------------------------------------------------------------------

  Widget _buildNextAlarm(BuildContext context) {
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, alarmState) {
        final now = DateTime.now();

        // If something is ringing, the card shows THAT alarm (looked up by id)
        // regardless of whether it's still the "soonest" — a one-time alarm that
        // just fired has no future occurrence, so keying off _nextAlarmEntry
        // alone would hide the ring. Otherwise show the soonest upcoming alarm.
        final ringingId = alarmState.ringingAlarmId;
        Alarm? ringingAlarm;
        if (ringingId != null) {
          for (final a in alarmState.alarms) {
            if (a.id == ringingId) {
              ringingAlarm = a;
              break;
            }
          }
        }
        final entry = _nextAlarmEntry(alarmState, now);
        if (ringingAlarm == null && entry == null) {
          return const SizedBox.shrink();
        }

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final is24Hour = settingsState.is24HourTime;
            if (ringingAlarm != null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _ringingCard(context, ringingAlarm, is24Hour),
              );
            }

            final activeNextAlarm = entry!.alarm;
            final nextOccurrence = entry.occurrence;
            // (entry is non-null here: the early-return above only spares us when
            // both ringingAlarm and entry are null, and ringingAlarm==null here.)
            final timeStr = AlarmTimeUtils.formatTime(
              activeNextAlarm.hour,
              activeNextAlarm.minute,
              is24Hour: is24Hour,
            );
            final primary = Theme.of(context).colorScheme.primary;

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: GlassCard(
                padding: const EdgeInsets.all(22),
                onTap: widget.onOpenAlarms,
                tintColor: primary,
                borderColor: primary.withValues(alpha: 0.4),
                borderWidth: 1,
                shadows: [
                  BoxShadow(
                    color: primary.withValues(alpha: 0.22),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
                child: Row(
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
                            color: Theme.of(context).colorScheme.onSurface,
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

  /// The big Home ringing card — mirrors the top ringing banner, larger. Uses
  /// the shared [RingingDismissal] so its button reads "Dismiss" / "Take Photo"
  /// / "Scan QR" exactly like the banner and the Alarms-tab row.
  Widget _ringingCard(BuildContext context, Alarm alarm, bool is24Hour) {
    final scheme = Theme.of(context).colorScheme;
    final error = scheme.error;
    final timeStr = AlarmTimeUtils.formatTime(
      alarm.hour,
      alarm.minute,
      is24Hour: is24Hour,
    );
    return GlassCard(
      padding: const EdgeInsets.all(24),
      tintColor: error,
      borderColor: error,
      borderWidth: 2,
      shadows: [
        BoxShadow(
          color: error.withValues(alpha: 0.24),
          blurRadius: 28,
          spreadRadius: -4,
        ),
      ],
      child: Column(
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
              color: scheme.onSurface,
              fontSize: 52,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            alarm.displayName,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            RingingDismissal.instruction(alarm),
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: error,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: const Size(0, 60),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () => RingingDismissal.trigger(context, alarm),
              // Min-height + a Flexible label: bold/large accessibility text
              // wraps to a second line and the button grows, instead of the
              // dismiss label being clipped on the ringing screen.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(RingingDismissal.actionIcon(alarm), size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      RingingDismissal.actionLabel(alarm).toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
            onTap: () => showCreateTimerSheet(context),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Recent activity
  // ---------------------------------------------------------------------

  /// Bottom "Details" block: the less-critical, at-a-glance facts (clock name,
  /// last sync) in a compact row of cells, plus the sync summary and a Sync Now
  /// action — moved here so the top of the dashboard stays focused.
  Widget _buildDetails() {
    return WakeSection(
      title: 'Details',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _deviceCell()),
              const SizedBox(width: 12),
              Expanded(child: _lastSyncCell()),
            ],
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(18),
            shadows: wakeCardShadow(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSyncSummary(),
                const SizedBox(height: 12),
                ValueListenableBuilder<bool>(
                  valueListenable: clockSyncInProgress,
                  builder: (context, syncing, _) => WakeSecondaryButton(
                    label: syncing ? 'Synchronizing…' : 'Sync Now',
                    icon: Icons.sync_rounded,
                    // Disabled only while a sync is already running; otherwise
                    // always enabled (disconnected is explained in the flow).
                    onPressed: syncing ? null : () => _syncNow(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One compact stat cell used in the Details row (icon + label + value).
  Widget _statCell(String title, String value, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(14),
      shadows: wakeCardShadow(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceCell() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        final name = bleState is BleConnected
            ? (bleState.device.platformName.isEmpty
                  ? 'WakeGuard Clock'
                  : bleState.device.platformName)
            : 'Not paired';
        return _statCell('Device', name, Icons.watch_rounded);
      },
    );
  }

  Widget _lastSyncCell() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      buildWhen: (prev, curr) => prev.is24HourTime != curr.is24HourTime,
      builder: (context, settings) => ValueListenableBuilder<DateTime?>(
        valueListenable: lastClockSync,
        builder: (context, lastSync, _) => _statCell(
          'Last sync',
          lastSync == null
              ? 'Never'
              : AlarmTimeUtils.formatSyncTimestamp(
                  lastSync,
                  is24Hour: settings.is24HourTime,
                ),
          Icons.history_rounded,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Behaviors (unchanged flows)
  // ---------------------------------------------------------------------

  Future<void> _syncNow(BuildContext context) async {
    final bleState = context.read<BleConnectionBloc>().state;
    if (bleState is! BleConnected) {
      showAppSnackBar(
        context,
        'Connect to the clock before syncing.',
        type: AppSnackType.error,
      );
      return;
    }
    await syncConnectedClock(context, bleState.device, showSuccess: true);
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
