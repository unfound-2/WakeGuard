import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ble/ble_payloads.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/repositories/ble_repository.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/ble_bloc/ble_event.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../alarm_edit_screen.dart';
import '../scanner_screen.dart';
import '../item_scan_screen.dart';
import '../../../domain/entities/alarm.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Your clock, at a glance',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 20),
                _buildConnectionStatus(),
                _buildSyncSummary(),
                const SizedBox(height: 16),
                _PeriodicRebuild(
                  interval: const Duration(seconds: 30),
                  builder: (context) => _buildNextAlarm(context),
                ),
                const SizedBox(height: 28),
                _sectionLabel(context, 'QUICK ACTIONS'),
                const SizedBox(height: 14),
                GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Make cards taller as text scales up so large accessibility
                  // font sizes don't overflow the card content.
                  childAspectRatio:
                      (1.1 / MediaQuery.textScalerOf(context).scale(1.0)).clamp(
                        0.62,
                        1.2,
                      ),
                  children: [
                    _buildActionCard(
                      context,
                      'Create Alarm',
                      Icons.add_alarm_rounded,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AlarmEditScreen(),
                          ),
                        );
                      },
                    ),
                    _buildActionCard(
                      context,
                      'Start Timer',
                      Icons.timer_rounded,
                      () => _showTimerDialog(context),
                    ),
                    _buildActionCard(
                      context,
                      'Sync Now',
                      Icons.sync_rounded,
                      () => _syncNow(context),
                    ),
                    _buildActionCard(
                      context,
                      'Scan QR',
                      Icons.qr_code_scanner_rounded,
                      () => _openScanner(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
        letterSpacing: 2,
        fontSize: 12,
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        String deviceName = 'No Device Connected';
        String status = 'Tap to Pair';
        Color color = Theme.of(context).colorScheme.error;
        IconData icon = Icons.bluetooth_disabled_rounded;

        final bool busy = bleState is BleConnecting || bleState is BleScanning;
        if (bleState is BleConnected) {
          deviceName = bleState.device.platformName.isEmpty
              ? 'Smart Clock'
              : bleState.device.platformName;
          status = 'Connected';
          color = AppColors.success;
          icon = Icons.bluetooth_connected_rounded;
        } else if (busy) {
          status = 'Connecting…';
          color = Theme.of(context).colorScheme.primary;
          icon = Icons.bluetooth_searching_rounded;
        } else {
          // Disconnected: the app only holds the link while open, so offer a
          // one-tap reconnect to the remembered clock.
          status = 'Tap to connect';
        }

        return GlassCard(
          // Reconnect on demand when disconnected; the clock keeps running
          // alarms on its own, so we don't hold the connection continuously.
          onTap: (bleState is BleConnected || busy)
              ? null
              : () => context.read<BleConnectionBloc>().add(ReconnectEvent()),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.4)),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      deviceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Compact "N of M alarms synced" line under the connection card, so the user
  /// can trust at a glance that the clock actually has their alarms — the app is
  /// usually disconnected (on-demand BLE), so "saved" and "live" can diverge.
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
          text = total == 1 ? 'Alarm synced to clock' : 'All $total alarms synced';
        } else {
          color = failed > 0
              ? Theme.of(context).colorScheme.error
              : const Color(0xFFF59E0B);
          icon = failed > 0
              ? Icons.error_outline_rounded
              : Icons.cloud_upload_rounded;
          final pending = total - synced;
          text = failed > 0
              ? '$synced of $total synced · $failed failed'
              : '$synced of $total synced · $pending pending';
        }

        return Padding(
          padding: const EdgeInsets.only(top: 10, left: 4),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNextAlarm(BuildContext context) {
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, alarmState) {
        if (alarmState.alarms.isEmpty) {
          return const SizedBox.shrink();
        }

        final activeAlarms = alarmState.alarms
            .where((a) => a.isActive)
            .toList();
        if (activeAlarms.isEmpty) {
          return const SizedBox.shrink();
        }

        final now = DateTime.now();
        final occurrences =
            activeAlarms
                .map(
                  (alarm) => (
                    alarm: alarm,
                    occurrence: AlarmTimeUtils.nextOccurrence(alarm, from: now),
                  ),
                )
                .where((entry) => entry.occurrence != null)
                .toList()
              ..sort((a, b) => a.occurrence!.compareTo(b.occurrence!));

        if (occurrences.isEmpty) return const SizedBox.shrink();
        final activeNextAlarm = occurrences.first.alarm;
        final nextOccurrence = occurrences.first.occurrence!;
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

            return GlassCard(
              padding: const EdgeInsets.all(22),
              tintColor: isRinging ? error : primary,
              borderColor: isRinging ? error : primary.withValues(alpha: 0.4),
              borderWidth: isRinging ? 2 : 1,
              shadows: [
                BoxShadow(
                  color: (isRinging ? error : primary).withValues(alpha: 0.22),
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
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: error,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            icon: Icon(
                              usesItem
                                  ? Icons.center_focus_strong_rounded
                                  : Icons.qr_code_scanner_rounded,
                              size: 26,
                            ),
                            label: Text(
                              usesItem
                                  ? 'SCAN ITEM TO DISMISS'
                                  : 'SCAN QR TO DISMISS',
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
            );
          },
        );
      },
    );
  }

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    return GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: primary, size: 26),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

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

    final repo = context.read<BleRepository>();
    final alarmBloc = context.read<AlarmBloc>();
    final settings = context.read<SettingsBloc>().state;

    try {
      await repo.sendCommand(bleState.device, 0x04, const []);
      await repo.sendCommand(
        bleState.device,
        0x01,
        BlePayloads.currentEpochSeconds(),
      );
      final alarmSync = Completer<void>();
      alarmBloc.add(
        SyncAlarmsToDeviceEvent(bleState.device, completer: alarmSync),
      );
      await alarmSync.future;
      await repo.sendCommand(
        bleState.device,
        0x06,
        BlePayloads.clockSettings(
          autoDim: settings.autoDim,
          sleepStartHour: settings.sleepStartHour,
          sleepStartMinute: settings.sleepStartMinute,
          sleepEndHour: settings.sleepEndHour,
          sleepEndMinute: settings.sleepEndMinute,
        ),
      );
      await repo.sendCommand(bleState.device, 0x05, const []);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clock sync complete.'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Clock sync failed.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
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

  void _openScanner(BuildContext context) {
    final alarmState = context.read<AlarmBloc>().state;
    final ringingAlarmId = alarmState.ringingAlarmId;
    if (ringingAlarmId != null) {
      final ringing = alarmState.alarms.where((a) => a.id == ringingAlarmId);
      if (ringing.isNotEmpty) {
        _pushDismissal(context, ringing.first);
        return;
      }
    }

    final taskAlarms = alarmState.alarms
        .where((alarm) => alarm.qrRequired)
        .toList();
    if (taskAlarms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No protected alarms are available.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (taskAlarms.length == 1) {
      _pushDismissal(context, taskAlarms.first);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Choose alarm',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              for (final alarm in taskAlarms)
                ListTile(
                  leading: Icon(
                    alarm.usesItemScan
                        ? Icons.center_focus_strong
                        : Icons.qr_code,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    AlarmTimeUtils.formatTime(
                      alarm.hour,
                      alarm.minute,
                      is24Hour: context.read<SettingsBloc>().state.is24HourTime,
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Text(
                    AlarmTimeUtils.formatDays(alarm.dayMask),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _pushDismissal(context, alarm);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Rebuilds [builder] on a fixed [interval] so relative time labels (e.g. the
/// "next alarm in 7h 20m" countdown) stay current without a full screen rebuild.
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
