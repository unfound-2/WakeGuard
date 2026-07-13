import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/core/utils/alarm_time_utils.dart';
import 'package:smart_ble_alarm/features/history/presentation/cubit/dismissal_history_cubit.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';

/// Read-only log of past alarm dismissals, with an option to clear it.
class DismissalHistoryScreen extends StatelessWidget {
  const DismissalHistoryScreen({super.key});

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

  String _formatTimestamp(DateTime t, bool is24Hour) {
    final time = AlarmTimeUtils.formatTime(
      t.hour,
      t.minute,
      is24Hour: is24Hour,
    );
    return '${_months[t.month - 1]} ${t.day}, $time';
  }

  @override
  Widget build(BuildContext context) {
    final is24Hour = context.watch<SettingsBloc>().state.is24HourTime;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dismissal History'),
        actions: [
          BlocBuilder<DismissalHistoryCubit, List<DismissalRecord>>(
            builder: (context, records) {
              if (records.isEmpty) return const SizedBox.shrink();
              return IconButton(
                tooltip: 'Clear history',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _confirmClear(context),
              );
            },
          ),
        ],
      ),
      body: GlassBackground(
        child: SafeArea(
          child: BlocBuilder<DismissalHistoryCubit, List<DismissalRecord>>(
            builder: (context, records) {
              if (records.isEmpty) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: const [
                    SizedBox(height: 40),
                    WakeEmptyState(
                      title: 'No dismissals yet',
                      message: 'Completed alarm dismissals will appear here.',
                      icon: Icons.history_rounded,
                    ),
                  ],
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: records.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final record = records[index];
                  final isItem = record.method == 'Item';
                  final primary = Theme.of(context).colorScheme.primary;
                  final title = record.label?.trim().isNotEmpty == true
                      ? record.label!.trim()
                      : 'Alarm ${record.alarmId}';
                  return GlassCard(
                    padding: const EdgeInsets.all(16),
                    borderRadius: 22,
                    shadows: wakeCardShadow(context),
                    child: Row(
                      children: [
                        Expanded(
                          child: WakeActivityRow(
                            title: title,
                            subtitle: _formatTimestamp(record.time, is24Hour),
                            icon: isItem
                                ? Icons.center_focus_strong_rounded
                                : Icons.qr_code_scanner_rounded,
                          ),
                        ),
                        const SizedBox(width: 8),
                        WakeStatusPill(
                          label: isItem ? 'Item scan' : 'QR scan',
                          icon: isItem
                              ? Icons.center_focus_strong_rounded
                              : Icons.qr_code_scanner_rounded,
                          color: primary,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _confirmClear(BuildContext context) {
    final cubit = context.read<DismissalHistoryCubit>();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This permanently removes all recorded dismissals.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              cubit.clear();
              Navigator.pop(dialogContext);
            },
            child: Text(
              'Clear',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
