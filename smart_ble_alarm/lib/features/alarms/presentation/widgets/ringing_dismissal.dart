import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/ui/wake_haptics.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_state.dart';
import 'package:smart_ble_alarm/features/history/presentation/cubit/dismissal_history_cubit.dart';
import 'package:smart_ble_alarm/features/wake_challenge/presentation/screens/item_scan_screen.dart';
import 'package:smart_ble_alarm/features/wake_challenge/presentation/screens/scanner_screen.dart';

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
  static Future<bool> trigger(
    BuildContext context,
    Alarm alarm, {
    bool localOnly = false,
    DateTime? ringingSince,
  }) async {
    // With no clock connected there is no 0x09 to send, so dismissal must
    // resolve locally — this is what makes a phone-originated ring ("Ring on
    // this phone") dismissible offline instead of dead-ending on "clock not
    // connected". The wake challenge (QR/photo) is still fully enforced; only
    // the redundant attempt to message an absent clock is skipped. When a clock
    // IS connected the behaviour is unchanged (dismissal is sent to it).
    final effectiveLocalOnly =
        localOnly ||
        context.read<BleConnectionBloc>().state is! BleConnected;
    if (alarm.qrRequired) {
      final dismissed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => alarm.usesItemScan
              ? ItemScanScreen(
                  alarm: alarm,
                  dismissLocally: effectiveLocalOnly,
                  ringingSinceOverride: ringingSince,
                )
              : ScannerScreen(
                  alarmId: alarm.id,
                  dismissLocally: effectiveLocalOnly,
                ),
        ),
      );
      return dismissed == true;
    }
    return _dismissNoTask(context, alarm, localOnly: effectiveLocalOnly);
  }

  static Future<bool> _dismissNoTask(
    BuildContext context,
    Alarm alarm, {
    required bool localOnly,
  }) async {
    // Capture everything context-bound before the first await.
    final alarmBloc = context.read<AlarmBloc>();
    final messenger = ScaffoldMessenger.of(context);
    final bleState = localOnly ? null : context.read<BleConnectionBloc>().state;
    BleRepository? repo;
    DismissalHistoryCubit? history;
    if (!localOnly) {
      try {
        repo = context.read<BleRepository>();
      } catch (_) {}
    }
    try {
      history = context.read<DismissalHistoryCubit>();
    } catch (_) {}

    if (bleState is BleConnected && repo != null) {
      try {
        // An unsecured alarm accepts any token on the clock (tryDismiss returns
        // ok when !ringSecured), so a zero token is enough to stop the ring.
        await repo.sendCommand(bleState.device, 0x09, [
          alarm.id & 0xFF,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]);
      } catch (_) {
        // The clock has no buzzer auto-timeout, so a failed write means it is
        // still ringing. Do NOT clear the ringing state or record a dismissal
        // (that would falsely claim success and drop the in-app dismissal UI);
        // surface an error and let the user retry or press the clock's button.
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              "Couldn't confirm dismissal with the clock. Try again, or "
              "press the clock's button.",
            ),
            backgroundColor: AppColors.error,
          ),
        );
        return false;
      }
    }
    alarmBloc.add(const SetRingingAlarmEvent(null));
    history?.record(alarmId: alarm.id, method: 'Dismiss', label: alarm.label);
    WakeHaptics.heavyImpact();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Alarm dismissed.'),
        backgroundColor: AppColors.success,
      ),
    );
    return true;
  }
}
