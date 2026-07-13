import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_ble_alarm/core/ui/app_snackbar.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/domain/clock_sync_service.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';

export 'package:smart_ble_alarm/features/bluetooth/domain/clock_sync_service.dart'
    show clockSyncInProgress, lastClockSync, loadLastClockSync;

Future<void> pushWeatherToClock(
  BleRepository repo,
  BluetoothDevice device,
  SettingsState settings,
) {
  return clockSyncService.pushWeatherToClock(repo, device, settings);
}

Future<bool> syncConnectedClock(
  BuildContext context,
  BluetoothDevice device, {
  bool showSuccess = false,
}) {
  final repo = context.read<BleRepository>();
  final alarmBloc = context.read<AlarmBloc>();
  final settingsBloc = context.read<SettingsBloc>();

  return clockSyncService.syncConnectedClock(
    repo: repo,
    alarmBloc: alarmBloc,
    settingsProvider: () => settingsBloc.state,
    device: device,
    userInitiated: showSuccess,
    onSuccess: (message) {
      if (!context.mounted) return;
      showAppSnackBar(context, message, type: AppSnackType.success);
    },
    onFailure: (message) {
      if (!context.mounted) return;
      showAppSnackBar(context, message, type: AppSnackType.error);
    },
  );
}
