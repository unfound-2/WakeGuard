import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/ble/ble_payloads.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/repositories/ble_repository.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import 'dart:ui' as dart_ui;
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../alarm_edit_screen.dart';
import '../scanner_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: Theme.of(context).brightness == Brightness.dark
              ? [
                  (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F111A)
                      : const Color(0xFFF3F4F6)),
                  Colors.black,
                ]
              : [
                  (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF0F111A)
                      : const Color(0xFFF3F4F6)),
                  Colors.white,
                ],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'DASHBOARD',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              _buildConnectionStatus(),
              const SizedBox(height: 16),
              _buildNextAlarm(context),
              const SizedBox(height: 24),
              Text(
                'QUICK ACTIONS',
                style: TextStyle(
                  color: (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF8B9BB4)
                      : const Color(0xFF6B7280)),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildActionCard(
                      context,
                      'Create Alarm',
                      Icons.add_alarm,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AlarmEditScreen(),
                          ),
                        );
                      },
                    ),
                    _buildActionCard(context, 'Start Timer', Icons.timer, () {
                      _showTimerDialog(context);
                    }),
                    _buildActionCard(context, 'Sync Now', Icons.sync, () {
                      _syncNow(context);
                    }),
                    _buildActionCard(
                      context,
                      'Wake Challenge',
                      Icons.center_focus_strong,
                      () {
                        _openScanner(context);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        String deviceName = 'No Device Connected';
        String status = 'Tap to Pair';
        Color color = Theme.of(context).colorScheme.error;

        if (bleState is BleConnected) {
          deviceName = bleState.device.platformName;
          status = 'Connected';
          color = const Color(0xFF4ADE80); // Success green
        } else if (bleState is BleConnecting || bleState is BleScanning) {
          status = 'Connecting...';
          color = Theme.of(context).colorScheme.primary;
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: dart_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.3),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.bluetooth, color: color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          deviceName,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        Text(
                          status,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
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

            return ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: BackdropFilter(
                filter: dart_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isRinging
                        ? Theme.of(
                            context,
                          ).colorScheme.error.withValues(alpha: 0.2)
                        : Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                    border: Border.all(
                      color: isRinging
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3),
                      width: isRinging ? 2 : 1,
                    ),
                  ),
                  child: isRinging
                      ? Column(
                          children: [
                            Text(
                              'ALARM RINGING',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              timeStr,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Verify ${settingsState.wakeObjectName} to dismiss.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color:
                                    Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? const Color(0xFF8B9BB4)
                                    : const Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.error,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(
                                Icons.center_focus_strong,
                                size: 28,
                              ),
                              label: const Text(
                                'VERIFY WAKE OBJECT',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ScannerScreen(
                                      alarmId: activeNextAlarm.id,
                                    ),
                                  ),
                                );
                              },
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
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  AlarmTimeUtils.formatNextOccurrence(
                                    nextOccurrence,
                                    now,
                                  ),
                                  style: TextStyle(
                                    color:
                                        (Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? const Color(0xFF8B9BB4)
                                        : const Color(0xFF6B7280)),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            Icon(
                              Icons.alarm_on,
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.5),
                              size: 48,
                            ),
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

  Widget _buildActionCard(
    BuildContext context,
    String title,
    IconData icon,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: dart_ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.3),
              border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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
                      color: (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF8B9BB4)
                          : const Color(0xFF6B7280)),
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

  void _openScanner(BuildContext context) {
    final alarmState = context.read<AlarmBloc>().state;
    final ringingAlarmId = alarmState.ringingAlarmId;
    if (ringingAlarmId != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScannerScreen(alarmId: ringingAlarmId),
        ),
      );
      return;
    }

    final qrAlarms = alarmState.alarms
        .where((alarm) => alarm.qrRequired)
        .toList();
    if (qrAlarms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No challenge-protected alarms are available.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    if (qrAlarms.length == 1) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ScannerScreen(alarmId: qrAlarms.first.id),
        ),
      );
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
              for (final alarm in qrAlarms)
                ListTile(
                  leading: Icon(
                    Icons.alarm,
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
                      color: (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF8B9BB4)
                          : const Color(0xFF6B7280)),
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScannerScreen(alarmId: alarm.id),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
