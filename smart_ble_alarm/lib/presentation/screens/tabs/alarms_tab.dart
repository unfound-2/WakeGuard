import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../domain/entities/alarm.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../alarm_edit_screen.dart';
import '../scanner_screen.dart';
import '../../../domain/usecases/print_qr_code.dart';
import '../../../data/datasources/secure_key_datasource.dart';

class AlarmsTab extends StatelessWidget {
  const AlarmsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Container(
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: TabBar(
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor:
                      (Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF8B9BB4)
                      : const Color(0xFF6B7280)),
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
    return Center(
      child: Text(
        'No active timers.',
        style: TextStyle(
          color: (Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF8B9BB4)
              : const Color(0xFF6B7280)),
          fontSize: 16,
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
              return Center(
                child: Text(
                  'No alarms yet. Tap + to add one.',
                  style: TextStyle(
                    color: (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF8B9BB4)
                        : const Color(0xFF6B7280)),
                  ),
                ),
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
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                          color:
                                              (Theme.of(context).brightness ==
                                                  Brightness.dark
                                              ? const Color(0xFF8B9BB4)
                                              : const Color(0xFF6B7280)),
                                        ),
                                      ),
                                    ],
                                    if (alarm.qrRequired) ...[
                                      const SizedBox(height: 16),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          OutlinedButton.icon(
                                            icon: Icon(
                                              Icons.print,
                                              size: 16,
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                            label: Text(
                                              'Print Backup',
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
                                                await usecase.execute(alarm.id);
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
                                            icon: const Icon(
                                              Icons.center_focus_strong,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            label: const Text(
                                              'Verify',
                                              style: TextStyle(
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
                                                  builder: (_) => ScannerScreen(
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
                                    activeThumbColor: Theme.of(
                                      context,
                                    ).colorScheme.primary,
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
                                        _confirmDelete(context, alarm);
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
    if (alarmBloc.state.alarms.length >= 5) {
      _showError(
        context,
        'The clock supports up to 5 alarms. Delete one before duplicating.',
      );
      return;
    }

    final duplicate = alarm.copyWith(id: _nextAlarmId(alarmBloc.state.alarms));
    alarmBloc.add(AddOrUpdateAlarmEvent(duplicate, _connectedDevice(context)));
  }

  void _confirmDelete(BuildContext context, Alarm alarm) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete alarm?'),
        content: Text(
          'This removes ${AlarmTimeUtils.formatTime(alarm.hour, alarm.minute, is24Hour: true)} from the app and clock.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              context.read<AlarmBloc>().add(
                DeleteAlarmEvent(alarm.id, _connectedDevice(context)),
              );
            },
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
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
