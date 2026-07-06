import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../domain/entities/alarm.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../widgets/empty_state.dart';
import '../alarm_edit_screen.dart';
import '../scanner_screen.dart';
import '../item_scan_screen.dart';
import '../../../domain/usecases/print_qr_code.dart';
import '../../../data/datasources/secure_key_datasource.dart';

class AlarmsTab extends StatelessWidget {
  const AlarmsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
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
            Expanded(child: _buildAlarmsList()),
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
              return EmptyState(
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
                    final syncStatus = state.syncStatusFor(alarm);
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
                                    _SyncStatusChip(syncStatus),
                                    const SizedBox(height: 10),
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

/// Compact pill showing whether an alarm's current settings are actually live
/// on the clock. With on-demand BLE the phone is often disconnected while
/// alarms are edited, so this tells the user at a glance which alarms the
/// hardware will really ring versus which are still waiting to upload.
class _SyncStatusChip extends StatelessWidget {
  final AlarmSyncStatus status;
  const _SyncStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    // Amber (pending) reads as "attention, not error" — the change is safely
    // saved, it just hasn't reached the hardware yet.
    final (Color color, IconData icon, String label) = switch (status) {
      AlarmSyncStatus.synced => (
        AppColors.success,
        Icons.check_circle_rounded,
        'On clock',
      ),
      AlarmSyncStatus.pending => (
        const Color(0xFFF59E0B),
        Icons.sync_rounded,
        'Pending sync',
      ),
      AlarmSyncStatus.failed => (
        Theme.of(context).colorScheme.error,
        Icons.error_rounded,
        'Sync failed',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}
