import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/glass.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../../widgets/empty_state.dart';

class TimersTab extends StatelessWidget {
  const TimersTab({super.key});

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
                  'Timers',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            const Expanded(child: _TimersList()),
          ],
        ),
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
  // With an empty list this costs nothing — important because the tab stays
  // mounted in the IndexedStack even while another tab is on screen.
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
          return const EmptyState(
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
