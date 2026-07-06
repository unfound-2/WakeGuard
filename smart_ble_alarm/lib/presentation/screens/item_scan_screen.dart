import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/wake_widgets.dart';
import '../../data/datasources/image_recognition_datasource.dart';
import '../../data/datasources/secure_key_datasource.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/repositories/ble_repository.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../blocs/history_cubit/dismissal_history_cubit.dart';

/// Dismisses an item-scan alarm by photographing the required object and
/// verifying it with the on-device image recogniser. On a match it sends the
/// same secured `0x09 ALARM_DISMISS` command a QR dismissal would.
class ItemScanScreen extends StatefulWidget {
  final Alarm alarm;
  const ItemScanScreen({super.key, required this.alarm});

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

  /// Failed match attempts this session. On-device labelling can simply never
  /// recognise the target (bad lighting, unusual object), which would otherwise
  /// trap the user with a ringing clock. After [_maxAttemptsBeforeFallback]
  /// misses we surface a manual dismissal escape hatch.
  int _failedAttempts = 0;
  static const int _maxAttemptsBeforeFallback = 3;

  @override
  void dispose() {
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
          _failedAttempts++;
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
      HapticFeedback.heavyImpact();
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
                if (_failedAttempts >= _maxAttemptsBeforeFallback)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextButton.icon(
                      onPressed: _isProcessing ? null : _dismiss,
                      icon: const Icon(Icons.lock_open_rounded, size: 18),
                      label: const Text("Can't scan the item? Dismiss anyway"),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
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
