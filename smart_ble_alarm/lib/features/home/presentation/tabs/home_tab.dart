import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:smart_ble_alarm/core/ble/clock_sync.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/ui/app_snackbar.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/core/ui/wake_haptics.dart';
import 'package:smart_ble_alarm/core/utils/alarm_time_utils.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/features/account/presentation/cubit/account_cubit.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_event.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_state.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:smart_ble_alarm/features/timers/presentation/cubit/countdown_timer_cubit.dart';
import 'package:smart_ble_alarm/features/timers/presentation/widgets/create_timer_sheet.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/screens/alarm_edit_screen.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/widgets/ringing_dismissal.dart';

/// The Home dashboard: a wake-up control center that leads with the next
/// protected alarm, then shows clock/sync/backup confidence, upcoming alarms,
/// and the primary actions on the shared liquid-glass system.
class HomeTab extends StatefulWidget {
  /// Switches the app to the Alarms tab (wired from MainScreen). Lets the
  /// next-alarm and live-timer cards act as shortcuts into the Alarms screen.
  final VoidCallback? onOpenAlarms;

  /// Turns this device into the full-screen Dedicated Clock, when the app-level
  /// route exposes that flow.
  final VoidCallback? onSetupDedicatedClock;

  const HomeTab({super.key, this.onOpenAlarms, this.onSetupDedicatedClock});

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
            const SizedBox(height: 18),
            _PeriodicRebuild(
              interval: const Duration(seconds: 30),
              builder: (context) => _buildWakeUpHero(context),
            ),
            _buildLiveTimers(),
            _buildProtectionStatus(),
            const SizedBox(height: 24),
            _buildUpcomingAlarms(),
            _buildActionBar(),
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
        return BlocBuilder<AccountCubit, AccountState>(
          buildWhen: (prev, curr) => prev.displayName != curr.displayName,
          builder: (context, account) {
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
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _personalGreeting(account),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _personalGreeting(AccountState account) {
    final name = account.displayName?.trim();
    final firstName = name == null || name.isEmpty
        ? null
        : name.split(RegExp(r'\s+')).first;
    final hour = DateTime.now().hour;
    final partOfDay = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';
    if (firstName == null) return '$partOfDay.';
    return '$partOfDay, $firstName.';
  }
  // ---------------------------------------------------------------------
  // Protection status
  // ---------------------------------------------------------------------

  Widget _buildProtectionStatus() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        return BlocBuilder<AlarmBloc, AlarmState>(
          builder: (context, alarmState) {
            return BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settings) {
                return ValueListenableBuilder<DateTime?>(
                  valueListenable: lastClockSync,
                  builder: (context, lastSync, _) {
                    return ValueListenableBuilder<bool>(
                      valueListenable: clockSyncInProgress,
                      builder: (context, syncing, _) {
                        final tiles = [
                          _clockProtectionTile(context, bleState),
                          _syncProtectionTile(
                            context,
                            alarmState,
                            settings,
                            lastSync,
                            syncing,
                          ),
                          _backupProtectionTile(context, settings),
                        ];

                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final stacked = constraints.maxWidth < 345;
                            if (stacked) {
                              return Column(
                                children: [
                                  for (var i = 0; i < tiles.length; i++) ...[
                                    if (i > 0) const SizedBox(height: 10),
                                    tiles[i],
                                  ],
                                ],
                              );
                            }
                            return Row(
                              children: [
                                for (var i = 0; i < tiles.length; i++) ...[
                                  if (i > 0) const SizedBox(width: 10),
                                  Expanded(child: tiles[i]),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _clockProtectionTile(BuildContext context, BleState state) {
    final scheme = Theme.of(context).colorScheme;
    final busy = state is BleConnecting || state is BleScanning;

    if (state is BleConnected) {
      final name = state.device.platformName.isEmpty
          ? 'WakeGuard Clock'
          : state.device.platformName;
      return _protectionTile(
        context,
        title: 'Clock',
        value: 'Connected',
        caption: name,
        icon: Icons.bluetooth_connected_rounded,
        color: AppColors.success,
      );
    }

    if (busy) {
      return _protectionTile(
        context,
        title: 'Clock',
        value: 'Reconnecting',
        caption: 'Searching nearby',
        icon: Icons.bluetooth_searching_rounded,
        color: scheme.primary,
      );
    }

    return _protectionTile(
      context,
      title: 'Clock',
      value: 'Offline',
      caption: 'Tap to retry',
      icon: Icons.bluetooth_disabled_rounded,
      color: AppColors.warning,
      onTap: () => context.read<BleConnectionBloc>().add(ReconnectEvent()),
    );
  }

  Widget _syncProtectionTile(
    BuildContext context,
    AlarmState state,
    SettingsState settings,
    DateTime? lastSync,
    bool syncing,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final total = state.alarms.length;
    final failed = state.alarms
        .where((a) => state.syncStatusFor(a) == AlarmSyncStatus.failed)
        .length;
    final synced = state.syncedAlarmCount;
    final pending = total - synced;

    final Color color;
    final IconData icon;
    final String value;
    final String caption;
    final VoidCallback? onTap;

    if (syncing) {
      color = scheme.primary;
      icon = Icons.sync_rounded;
      value = 'Syncing';
      caption = 'Updating clock';
      onTap = null;
    } else if (total == 0) {
      color = scheme.onSurfaceVariant;
      icon = Icons.cloud_queue_rounded;
      value = 'No alarms';
      caption = 'Nothing to sync';
      onTap = null;
    } else if (failed > 0) {
      color = scheme.error;
      icon = Icons.error_rounded;
      value = '$failed failed';
      caption = 'Tap to retry';
      onTap = () => _syncNow(context);
    } else if (pending == 0) {
      color = AppColors.success;
      icon = Icons.cloud_done_rounded;
      value = 'Synced';
      caption = lastSync == null
          ? '$total on clock'
          : AlarmTimeUtils.formatSyncTimestamp(
              lastSync,
              is24Hour: settings.is24HourTime,
            );
      onTap = () => _syncNow(context);
    } else {
      color = AppColors.warning;
      icon = Icons.cloud_upload_rounded;
      value = '$pending pending';
      caption = 'Tap to sync';
      onTap = () => _syncNow(context);
    }

    return _protectionTile(
      context,
      title: 'Sync',
      value: value,
      caption: caption,
      icon: icon,
      color: color,
      onTap: onTap,
    );
  }

  Widget _backupProtectionTile(BuildContext context, SettingsState settings) {
    final enabled = settings.backupNotificationsEnabled;
    return _protectionTile(
      context,
      title: 'Backup',
      value: enabled ? 'On' : 'Off',
      caption: enabled ? 'Phone alerts' : 'Tap to enable',
      icon: enabled
          ? Icons.notifications_active_rounded
          : Icons.notifications_off_rounded,
      color: enabled ? AppColors.success : AppColors.warning,
      onTap: () => context.read<SettingsBloc>().add(
        ToggleBackupNotificationsEvent(!enabled),
      ),
    );
  }

  Widget _protectionTile(
    BuildContext context, {
    required String title,
    required String value,
    required String caption,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    final glass = GlassTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    // Light theme: the raw semantic `color` on caption text falls well below
    // 4.5:1 (icon + wash keep the saturated color). Use the on-surface color
    // for the caption text in light theme; dark theme already passes.
    final dark = glass.brightness == Brightness.dark;
    final captionColor = dark ? color : scheme.onSurface;
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(14),
      shadows: wakeCardShadow(context),
      onTap: onTap == null
          ? null
          : () {
              WakeHaptics.lightImpact();
              onTap();
            },
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 92),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const Spacer(),
                Icon(
                  onTap == null
                      ? Icons.check_rounded
                      : Icons.chevron_right_rounded,
                  size: 16,
                  color: onTap == null
                      ? glass.stroke.withValues(alpha: 0.7)
                      : scheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: captionColor),
            ),
          ],
        ),
      ),
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
                            done
                                ? "Time's up"
                                : _formatRemaining(soonest.remaining(now)),
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w800,
                              color: done ? scheme.error : scheme.onSurface,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
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

  // ---------------------------------------------------------------------
  // Next wake-up hero
  // ---------------------------------------------------------------------

  /// Upcoming occurrences across active alarms, soonest first.
  List<({Alarm alarm, DateTime occurrence})> _upcomingAlarmEntries(
    AlarmState state,
    DateTime now,
  ) {
    return state.alarms
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
  }

  /// The soonest upcoming occurrence across all active alarms, or null.
  ({Alarm alarm, DateTime occurrence})? _nextAlarmEntry(
    AlarmState state,
    DateTime now,
  ) {
    final entries = _upcomingAlarmEntries(state, now);
    return entries.isEmpty ? null : entries.first;
  }

  String _formatRemaining(Duration remaining) {
    String two(int v) => v.toString().padLeft(2, '0');
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);
    final s = remaining.inSeconds.remainder(60);
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  String _formatUntil(DateTime occurrence, DateTime now) {
    final remaining = occurrence.difference(now);
    if (remaining.inMinutes < 1) return 'soon';
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    if (days > 0) {
      return hours > 0 ? 'in ${days}d ${hours}h' : 'in ${days}d';
    }
    if (hours > 0) return 'in ${hours}h ${minutes}m';
    return 'in ${minutes}m';
  }

  Widget _buildWakeUpHero(BuildContext context) {
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

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            final is24Hour = settingsState.is24HourTime;
            if (ringingAlarm != null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: _ringingCard(context, ringingAlarm, is24Hour),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: entry == null
                  ? _emptyWakeUpHero(context)
                  : _nextWakeUpCard(
                      context,
                      alarmState,
                      entry.alarm,
                      entry.occurrence,
                      now,
                      is24Hour,
                    ),
            );
          },
        );
      },
    );
  }

  Widget _emptyWakeUpHero(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    return GlassCard(
      padding: const EdgeInsets.all(24),
      tintColor: primary,
      borderColor: primary.withValues(alpha: 0.34),
      borderWidth: 1,
      shadows: [
        BoxShadow(
          color: primary.withValues(alpha: 0.18),
          blurRadius: 26,
          spreadRadius: -6,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WakeStatusPill(
            label: 'No wake-up set',
            icon: Icons.shield_outlined,
            color: AppColors.warning,
          ),
          const SizedBox(height: 18),
          Text(
            'Set your next wake-up',
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add an alarm to protect your morning.',
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 22),
          WakePrimaryButton(
            label: 'Create Alarm',
            icon: Icons.add_alarm_rounded,
            onPressed: () => _openEditor(context),
          ),
        ],
      ),
    );
  }

  Widget _nextWakeUpCard(
    BuildContext context,
    AlarmState state,
    Alarm alarm,
    DateTime occurrence,
    DateTime now,
    bool is24Hour,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final timeStr = AlarmTimeUtils.formatTime(
      alarm.hour,
      alarm.minute,
      is24Hour: is24Hour,
    );
    final syncStatus = state.syncStatusFor(alarm);

    return GlassCard(
      padding: const EdgeInsets.all(22),
      tintColor: primary,
      borderColor: primary.withValues(alpha: 0.4),
      borderWidth: 1,
      shadows: [
        BoxShadow(
          color: primary.withValues(alpha: 0.22),
          blurRadius: 28,
          spreadRadius: -6,
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              WakeStatusPill(
                label: 'Next Wake-Up',
                icon: Icons.shield_rounded,
                color: primary,
              ),
              const Spacer(),
              Switch.adaptive(
                value: alarm.isActive,
                onChanged: (enabled) => _toggleAlarm(context, alarm, enabled),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              timeStr,
              maxLines: 1,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 52,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${AlarmTimeUtils.formatNextOccurrence(occurrence, now)} · '
            '${_formatUntil(occurrence, now)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            alarm.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              WakeStatusPill(
                label: AlarmTimeUtils.formatDays(alarm.dayMask),
                icon: Icons.repeat_rounded,
                color: scheme.onSurfaceVariant,
              ),
              _dismissalPill(context, alarm),
              _syncStatusPill(context, syncStatus),
              if (alarm.snoozeEnabled)
                WakeStatusPill(
                  label: alarm.snoozeMaxCount > 0
                      ? 'Snooze x${alarm.snoozeMaxCount}'
                      : 'Snooze on',
                  icon: Icons.snooze_rounded,
                  color: scheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: WakeSecondaryButton(
                  label: 'Edit',
                  icon: Icons.edit_rounded,
                  onPressed: () => _openEditor(context, alarm: alarm),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WakeSecondaryButton(
                  label: 'All Alarms',
                  icon: Icons.format_list_bulleted_rounded,
                  onPressed: widget.onOpenAlarms,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  WakeStatusPill _dismissalPill(BuildContext context, Alarm alarm) {
    final scheme = Theme.of(context).colorScheme;
    if (alarm.usesItemScan) {
      return WakeStatusPill(
        label: 'Photo required',
        icon: Icons.camera_alt_rounded,
        color: scheme.primary,
      );
    }
    if (alarm.qrRequired) {
      return WakeStatusPill(
        label: 'QR required',
        icon: Icons.qr_code_scanner_rounded,
        color: scheme.primary,
      );
    }
    return WakeStatusPill(
      label: 'Normal dismiss',
      icon: Icons.touch_app_rounded,
      color: scheme.onSurfaceVariant,
    );
  }

  WakeStatusPill _syncStatusPill(BuildContext context, AlarmSyncStatus status) {
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
          Semantics(
            liveRegion: true,
            label: 'Alarm ringing, $timeStr, ${alarm.displayName}',
            child: Text(
              'ALARM RINGING',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: error,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontSize: 15,
              ),
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
  // Upcoming timeline
  // ---------------------------------------------------------------------

  Widget _buildUpcomingAlarms() {
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, alarmState) {
        return BlocBuilder<SettingsBloc, SettingsState>(
          buildWhen: (prev, curr) => prev.is24HourTime != curr.is24HourTime,
          builder: (context, settings) {
            final now = DateTime.now();
            final entries = _upcomingAlarmEntries(
              alarmState,
              now,
            ).take(3).toList();
            if (entries.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: WakeSection(
                title: 'Upcoming',
                child: GlassCard(
                  borderRadius: 24,
                  padding: EdgeInsets.zero,
                  shadows: wakeCardShadow(context),
                  child: Column(
                    children: [
                      for (var i = 0; i < entries.length; i++) ...[
                        if (i > 0) _timelineDivider(context),
                        _upcomingAlarmRow(
                          context,
                          entries[i].alarm,
                          entries[i].occurrence,
                          now,
                          settings.is24HourTime,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _timelineDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 18),
      child: Divider(
        height: 1,
        thickness: 1,
        color: GlassTheme.of(context).stroke,
      ),
    );
  }

  Widget _upcomingAlarmRow(
    BuildContext context,
    Alarm alarm,
    DateTime occurrence,
    DateTime now,
    bool is24Hour,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final time = AlarmTimeUtils.formatTime(
      alarm.hour,
      alarm.minute,
      is24Hour: is24Hour,
    );
    final date = AlarmTimeUtils.formatNextOccurrence(occurrence, now);

    return Semantics(
      button: true,
      label: 'Edit alarm, $time, ${alarm.displayName}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          WakeHaptics.lightImpact();
          _openEditor(context, alarm: alarm);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 86,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  time,
                  maxLines: 1,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alarm.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$date · ${_formatUntil(occurrence, now)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(_dismissalIcon(alarm), color: scheme.primary, size: 20),
          ],
        ),
      ),
      ),
    );
  }

  IconData _dismissalIcon(Alarm alarm) {
    if (alarm.usesItemScan) return Icons.camera_alt_rounded;
    if (alarm.qrRequired) return Icons.qr_code_scanner_rounded;
    return Icons.touch_app_rounded;
  }

  // ---------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------

  Widget _buildActionBar() {
    return WakeSection(
      title: 'Actions',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _dashboardAction(
              context,
              label: 'Add Alarm',
              icon: Icons.add_alarm_rounded,
              onTap: () => _openEditor(context),
            ),
            const SizedBox(width: 10),
            _dashboardAction(
              context,
              label: 'Timer',
              icon: Icons.timer_rounded,
              onTap: () => showCreateTimerSheet(context),
            ),
            const SizedBox(width: 10),
            ValueListenableBuilder<bool>(
              valueListenable: clockSyncInProgress,
              builder: (context, syncing, _) => _dashboardAction(
                context,
                label: syncing ? 'Syncing' : 'Sync',
                icon: Icons.sync_rounded,
                onTap: syncing ? null : () => _syncNow(context),
              ),
            ),
            if (widget.onSetupDedicatedClock != null) ...[
              const SizedBox(width: 10),
              _dashboardAction(
                context,
                label: 'Dedicated',
                icon: Icons.bedtime_rounded,
                onTap: widget.onSetupDedicatedClock,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dashboardAction(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    final color = enabled ? scheme.primary : scheme.onSurfaceVariant;
    return SizedBox(
      width: 104,
      child: GlassCard(
        borderRadius: 22,
        padding: const EdgeInsets.all(14),
        onTap: onTap == null
            ? null
            : () {
                WakeHaptics.lightImpact();
                onTap();
              },
        shadows: wakeCardShadow(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 78),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 18),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Behaviors (unchanged flows)
  // ---------------------------------------------------------------------

  void _openEditor(BuildContext context, {Alarm? alarm}) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AlarmEditScreen(alarm: alarm)),
    );
  }

  void _toggleAlarm(BuildContext context, Alarm alarm, bool enabled) {
    final updatedMask = enabled
        ? (alarm.dayMask | 0x80)
        : (alarm.dayMask & 0x7F);
    context.read<AlarmBloc>().add(
      AddOrUpdateAlarmEvent(
        alarm.copyWith(dayMask: updatedMask),
        _connectedDevice(context),
      ),
    );
  }

  BluetoothDevice? _connectedDevice(BuildContext context) {
    final bleState = context.read<BleConnectionBloc>().state;
    return bleState is BleConnected ? bleState.device : null;
  }

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
