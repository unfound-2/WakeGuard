import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/repositories/ble_repository.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/history_cubit/dismissal_history_cubit.dart';
import '../screens/item_scan_screen.dart';
import '../screens/scanner_screen.dart';

/// Shared, task-aware dismissal action for a ringing alarm. Used by the global
/// ringing banner, the Home ringing card, and the Alarms-tab row so the label,
/// icon, and behaviour can never drift apart across the three surfaces.
///
/// Three cases, keyed off the alarm's wake-challenge config:
///  * no task (`!qrRequired`)          -> "Dismiss"    (sends 0x09 directly)
///  * photo/item task (`usesItemScan`) -> "Take Photo" (opens ItemScanScreen)
///  * QR task (qrRequired & !item)     -> "Scan QR"    (opens ScannerScreen)
class RingingDismissal {
  const RingingDismissal._();

  static String actionLabel(Alarm alarm) {
    if (!alarm.qrRequired) return 'Dismiss';
    return alarm.usesItemScan ? 'Take Photo' : 'Scan QR';
  }

  static IconData actionIcon(Alarm alarm) {
    if (!alarm.qrRequired) return Icons.alarm_off_rounded;
    return alarm.usesItemScan
        ? Icons.center_focus_strong_rounded
        : Icons.qr_code_scanner_rounded;
  }

  /// One-line instruction shown alongside the button on each surface.
  static String instruction(Alarm alarm) {
    if (!alarm.qrRequired) return 'Tap dismiss to stop the alarm.';
    if (alarm.usesItemScan) {
      final label = alarm.itemLabel?.trim();
      final item = (label != null && label.isNotEmpty) ? label : 'the item';
      return 'Photograph $item to dismiss.';
    }
    return 'Scan the printed backup code to dismiss.';
  }

  /// Runs the correct dismissal for [alarm]: opens the scan/photo screen for a
  /// task alarm, or dismisses a no-task alarm outright (sending the same 0x09
  /// the clock accepts for unsecured alarms).
  static Future<void> trigger(BuildContext context, Alarm alarm) async {
    if (alarm.qrRequired) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => alarm.usesItemScan
              ? ItemScanScreen(alarm: alarm)
              : ScannerScreen(alarmId: alarm.id),
        ),
      );
      return;
    }
    await _dismissNoTask(context, alarm);
  }

  static Future<void> _dismissNoTask(BuildContext context, Alarm alarm) async {
    // Capture everything context-bound before the first await.
    final alarmBloc = context.read<AlarmBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final bleState = context.read<BleConnectionBloc>().state;
    BleRepository? repo;
    DismissalHistoryCubit? history;
    try {
      repo = context.read<BleRepository>();
    } catch (_) {}
    try {
      history = context.read<DismissalHistoryCubit>();
    } catch (_) {}

    if (bleState is BleConnected && repo != null) {
      try {
        // An unsecured alarm accepts any token on the clock (tryDismiss returns
        // ok when !ringSecured), so a zero token is enough to stop the ring.
        await repo.sendCommand(bleState.device, 0x09, [
          alarm.id & 0xFF,
          0, 0, 0, 0, 0, 0, 0, 0,
        ]);
      } catch (_) {
        // Fall through: still clear the local ringing state so the UI recovers
        // even if the write failed (the clock also self-silences on its button).
      }
    }
    alarmBloc.add(const SetRingingAlarmEvent(null));
    history?.record(alarmId: alarm.id, method: 'Dismiss', label: alarm.label);
    HapticFeedback.heavyImpact();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Alarm dismissed.'),
        backgroundColor: AppColors.success,
      ),
    );
  }
}
