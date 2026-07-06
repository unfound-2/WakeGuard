import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
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

    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Item to Dismiss')),
      body: GlassBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 112,
                    height: 112,
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
                      size: 56,
                      color: primary,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Find and photograph:',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description != null && description.trim().isNotEmpty
                      ? description
                      : target,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Recognises: $target',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (_statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _statusMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                      ),
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
                          Chip(
                            label: Text(
                              '${item.label} '
                              '(${(item.confidence * 100).round()}%)',
                            ),
                          ),
                      ],
                    ),
                  ),
                SizedBox(
                  height: 64,
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _scanItem,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.photo_camera, size: 26),
                    label: Text(
                      _isProcessing ? 'CHECKING…' : 'PHOTOGRAPH ITEM',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
