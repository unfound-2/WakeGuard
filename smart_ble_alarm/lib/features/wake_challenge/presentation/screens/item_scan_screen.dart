import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/core/ui/wake_haptics.dart';
import 'package:smart_ble_alarm/data/datasources/image_recognition_datasource.dart';
import 'package:smart_ble_alarm/data/datasources/secure_key_datasource.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_state.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/history/presentation/cubit/dismissal_history_cubit.dart';
import 'scanner_screen.dart';

/// Dismisses an item-scan alarm by photographing the required object and
/// verifying it with the on-device image recogniser. On a match it sends the
/// same secured `0x09 ALARM_DISMISS` command a QR dismissal would.
class ItemScanScreen extends StatefulWidget {
  final Alarm alarm;
  final bool dismissLocally;
  final DateTime? ringingSinceOverride;
  const ItemScanScreen({
    super.key,
    required this.alarm,
    this.dismissLocally = false,
    this.ringingSinceOverride,
  });

  @override
  State<ItemScanScreen> createState() => _ItemScanScreenState();
}

class _ItemScanScreenState extends State<ItemScanScreen> {
  final ImagePicker _picker = ImagePicker();
  final ImageRecognitionDatasource _recognizer = ImageRecognitionDatasource();
  final SecureKeyDatasource _secureKeyDatasource = SecureKeyDatasource();

  bool _isProcessing = false;
  String? _statusMessage;
  List<RecognizedItem> _lastDetected = const [];

  /// The printed backup QR is the ONLY bypass when the item can't be scanned,
  /// and it is gated: it only becomes available [_backupGate] after the alarm
  /// started ringing, so the user must genuinely attempt the wake task first.
  /// There is deliberately no free "dismiss anyway" escape.
  static const Duration _backupGate = Duration(minutes: 3);
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Tick every second so the "backup available in M:SS" countdown advances and
    // the backup button appears the moment the gate elapses.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recognizer.close();
    super.dispose();
  }

  Future<void> _scanItem() async {
    if (_isProcessing) return;

    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
    );
    if (photo == null || !mounted) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Checking the photo…';
      _lastDetected = const [];
    });

    try {
      final detected = await _recognizer.labelImageFile(photo.path);
      final target = widget.alarm.itemLabel ?? '';
      final matched = detected.any(
        (item) => ImageRecognitionDatasource.matchesLabel(item.label, target),
      );
      if (!mounted) return;

      if (!matched) {
        setState(() {
          _isProcessing = false;
          _lastDetected = detected.take(3).toList();
          _statusMessage = detected.isEmpty
              ? "Couldn't recognise anything. Try again with better lighting."
              : "That doesn't look like the right item. Point the camera at $target.";
        });
        return;
      }

      await _dismiss();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Could not process the photo. Please try again.';
      });
    }
  }

  Future<void> _dismiss() async {
    if (widget.dismissLocally) {
      final history = context.read<DismissalHistoryCubit>();
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      history.record(
        alarmId: widget.alarm.id,
        method: 'Item',
        label: widget.alarm.label,
      );
      WakeHaptics.heavyImpact();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Alarm Dismissed!'),
          backgroundColor: AppColors.success,
        ),
      );
      navigator.pop(true);
      return;
    }

    final bleState = context.read<BleConnectionBloc>().state;
    if (bleState is! BleConnected) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Item recognised, but the clock is not connected.';
      });
      return;
    }

    // Capture everything that needs BuildContext before awaiting.
    final repo = context.read<BleRepository>();
    final alarmBloc = context.read<AlarmBloc>();
    final history = context.read<DismissalHistoryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final token = await _secureKeyDatasource.getDailyToken(widget.alarm.id);
      await repo.sendCommand(bleState.device, 0x09, [
        widget.alarm.id & 0xFF,
        ...token,
      ]);
      if (!mounted) return;
      alarmBloc.add(const SetRingingAlarmEvent(null));
      history.record(
        alarmId: widget.alarm.id,
        method: 'Item',
        label: widget.alarm.label,
      );
      WakeHaptics.heavyImpact();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Alarm Dismissed!'),
          backgroundColor: AppColors.success,
        ),
      );
      navigator.pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _statusMessage =
            'Item recognised, but dismissal could not be sent to the clock.';
      });
    }
  }

  /// The gated backup-code affordance. While the alarm is ringing, shows a
  /// countdown until [_backupGate] elapses, then a button to scan the printed
  /// backup QR (the only sanctioned bypass — no free dismiss). Hidden entirely
  /// when this alarm isn't the one currently ringing (nothing to gate against).
  Widget _buildBackupGate(ColorScheme scheme) {
    final ringingSince =
        widget.ringingSinceOverride ??
        (() {
          final alarmState = context.read<AlarmBloc>().state;
          return alarmState.ringingAlarmId == widget.alarm.id
              ? alarmState.ringingSince
              : null;
        })();
    if (ringingSince == null) return const SizedBox.shrink();

    final remaining = _backupGate - DateTime.now().difference(ringingSince);
    if (remaining > Duration.zero) {
      final total = remaining.inSeconds;
      final mmss = '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          "Can't scan it? Backup code unlocks in $mmss",
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextButton.icon(
        onPressed: _isProcessing ? null : _openBackupScanner,
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
        label: const Text("Can't scan the item? Use the backup code"),
        style: TextButton.styleFrom(foregroundColor: scheme.primary),
      ),
    );
  }

  Future<void> _openBackupScanner() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerScreen(
          alarmId: widget.alarm.id,
          dismissLocally: widget.dismissLocally,
        ),
      ),
    );
    // The QR scanner dismissed the alarm — pop this screen too so the user lands
    // back on the (now cleared) home surface instead of the stale scan prompt.
    if (result == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.alarm.itemLabel ?? 'the item';
    final description = widget.alarm.itemDescription;

    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Scan Item to Dismiss')),
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),
                Center(
                  child: Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          primary.withValues(alpha: 0.28),
                          primary.withValues(alpha: 0.04),
                        ],
                      ),
                      border: Border.all(color: primary.withValues(alpha: 0.4)),
                    ),
                    child: Icon(
                      Icons.center_focus_strong_rounded,
                      size: 58,
                      color: primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                GlassCard(
                  borderRadius: 28,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 22,
                  ),
                  shadows: wakeCardShadow(context),
                  child: Column(
                    children: [
                      Text(
                        'Find and photograph',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        description != null && description.trim().isNotEmpty
                            ? description
                            : target,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      WakeStatusPill(
                        label: 'Recognises: $target',
                        icon: Icons.search_rounded,
                        color: primary,
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 3),
                if (_statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurface, fontSize: 15),
                    ),
                  ),
                if (_lastDetected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final item in _lastDetected)
                          WakeStatusPill(
                            label:
                                '${item.label} '
                                '(${(item.confidence * 100).round()}%)',
                            icon: Icons.label_outline_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ),
                _buildBackupGate(scheme),
                WakePrimaryButton(
                  label: _isProcessing ? 'Checking…' : 'Photograph Item',
                  icon: Icons.photo_camera_rounded,
                  onPressed: _isProcessing ? null : _scanItem,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
