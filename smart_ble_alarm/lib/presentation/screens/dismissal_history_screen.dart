import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/alarm_time_utils.dart';
import '../blocs/history_cubit/dismissal_history_cubit.dart';
import '../blocs/settings_bloc/settings_bloc.dart';

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
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'No dismissals recorded yet.\nCompleted alarm dismissals '
                      'will appear here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: records.length,
                itemBuilder: (context, index) {
                  final record = records[index];
                  final isItem = record.method == 'Item';
                  final primary = Theme.of(context).colorScheme.primary;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: GlassCard(
                      padding: const EdgeInsets.all(16),
                      borderRadius: 18,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: primary.withValues(alpha: 0.14),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isItem
                                  ? Icons.center_focus_strong_rounded
                                  : Icons.qr_code_scanner_rounded,
                              color: primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  record.label?.trim().isNotEmpty == true
                                      ? record.label!.trim()
                                      : 'Alarm ${record.alarmId}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatTimestamp(record.time, is24Hour),
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
                          Text(
                            isItem ? 'Item scan' : 'QR scan',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: primary,
                            ),
                          ),
                        ],
                      ),
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
