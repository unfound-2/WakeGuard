import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/ble/ble_payloads.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/wake_widgets.dart';
import '../../domain/repositories/ble_repository.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/timer_cubit/countdown_timer_cubit.dart';

/// Opens the shared glass timer-creation sheet used by both the Home quick
/// action and the Alarm tab's Timer subtab, so there is one timer UI.
Future<void> showCreateTimerSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    // No sheet elevation: the inner GlassCard carries its own soft shadow, and
    // the default sheet Material would otherwise draw a hard-edged shadow.
    elevation: 0,
    builder: (_) => const CreateTimerSheet(),
  );
}

/// Bottom sheet for creating a timer. Presents a glass wheel picker in the same
/// visual language as the alarm editor, then (on confirm) sends the duration to
/// the clock via the 0x0A command and registers a live local mirror.
class CreateTimerSheet extends StatefulWidget {
  const CreateTimerSheet({super.key});

  @override
  State<CreateTimerSheet> createState() => _CreateTimerSheetState();
}

class _CreateTimerSheetState extends State<CreateTimerSheet> {
  Duration _duration = const Duration(minutes: 15);
  bool _sending = false;

  Future<void> _start() async {
    final seconds = _duration.inSeconds;
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (seconds <= 0) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Choose a timer duration first.'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    final bleState = context.read<BleConnectionBloc>().state;
    if (bleState is! BleConnected) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Connect to the clock before starting a timer.'),
          backgroundColor: scheme.error,
        ),
      );
      return;
    }

    setState(() => _sending = true);
    try {
      await context.read<BleRepository>().sendCommand(
        bleState.device,
        0x0A,
        BlePayloads.uint32(seconds),
      );
      if (!mounted) return;
      context.read<CountdownTimerCubit>().startTimer(_duration);
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Timer started on clock!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Timer could not be sent to the clock.'),
          backgroundColor: scheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: GlassCard(
          borderRadius: 28,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          shadows: wakeCardShadow(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'New timer',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Runs on the clock; this list mirrors it live.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              _TimerWheelPicker(
                initial: _duration,
                onChanged: (d) => _duration = d,
              ),
              const SizedBox(height: 18),
              WakePrimaryButton(
                label: _sending ? 'Starting…' : 'Start timer',
                icon: Icons.play_arrow_rounded,
                onPressed: _sending ? null : _start,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three-wheel (hours / minutes / seconds) duration picker sharing one
/// liquid-glass selection band, matching the alarm editor's wheel style. The
/// wheels are evenly spaced and every value is zero-padded to two digits so the
/// numbers keep a consistent rhythm.
class _TimerWheelPicker extends StatefulWidget {
  final Duration initial;
  final ValueChanged<Duration> onChanged;

  const _TimerWheelPicker({required this.initial, required this.onChanged});

  @override
  State<_TimerWheelPicker> createState() => _TimerWheelPickerState();
}

class _TimerWheelPickerState extends State<_TimerWheelPicker> {
  static const double _itemExtent = 44;
  static const double _wheelWidth = 60;
  static const double _wheelGap = 26;

  late final FixedExtentScrollController _hCtrl;
  late final FixedExtentScrollController _mCtrl;
  late final FixedExtentScrollController _sCtrl;
  late int _h;
  late int _m;
  late int _s;

  @override
  void initState() {
    super.initState();
    _h = widget.initial.inHours.clamp(0, 23);
    _m = widget.initial.inMinutes % 60;
    _s = widget.initial.inSeconds % 60;
    _hCtrl = FixedExtentScrollController(initialItem: _h);
    _mCtrl = FixedExtentScrollController(initialItem: _m);
    _sCtrl = FixedExtentScrollController(initialItem: _s);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    _sCtrl.dispose();
    super.dispose();
  }

  void _emit() =>
      widget.onChanged(Duration(hours: _h, minutes: _m, seconds: _s));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final numberStyle = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w500,
      color: theme.colorScheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final captionStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _caption('HOURS', captionStyle),
            const SizedBox(width: _wheelGap),
            _caption('MINUTES', captionStyle),
            const SizedBox(width: _wheelGap),
            _caption('SECONDS', captionStyle),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Continuous selection band behind all three wheels.
              IgnorePointer(
                child: Container(
                  height: _itemExtent,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: primary.withValues(alpha: 0.18)),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _wheel(_hCtrl, 24, numberStyle, (i) {
                    _h = i;
                    _emit();
                  }),
                  const SizedBox(width: _wheelGap),
                  _wheel(_mCtrl, 60, numberStyle, (i) {
                    _m = i;
                    _emit();
                  }),
                  const SizedBox(width: _wheelGap),
                  _wheel(_sCtrl, 60, numberStyle, (i) {
                    _s = i;
                    _emit();
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _caption(String text, TextStyle style) {
    return SizedBox(
      width: _wheelWidth,
      child: Center(child: Text(text, style: style)),
    );
  }

  Widget _wheel(
    FixedExtentScrollController controller,
    int count,
    TextStyle numberStyle,
    ValueChanged<int> onSel,
  ) {
    return SizedBox(
      width: _wheelWidth,
      height: 176,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: _itemExtent,
        squeeze: 1.1,
        diameterRatio: 1.35,
        useMagnifier: true,
        magnification: 1.06,
        backgroundColor: Colors.transparent,
        selectionOverlay: const SizedBox.shrink(),
        onSelectedItemChanged: (i) {
          onSel(i);
          HapticFeedback.selectionClick();
        },
        children: [
          for (int i = 0; i < count; i++)
            Center(child: Text(i.toString().padLeft(2, '0'), style: numberStyle)),
        ],
      ),
    );
  }
}
