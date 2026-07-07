import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/repositories/ble_repository.dart';
import '../../presentation/blocs/alarm_bloc/alarm_bloc.dart';
import '../../presentation/blocs/settings_bloc/settings_bloc.dart';
import '../theme/app_colors.dart';
import 'ble_payloads.dart';

/// Wall-clock instant of the last successful full sync, surfaced on the Clock
/// tab and Home dashboard. Loaded lazily from SharedPreferences and updated by
/// [syncConnectedClock].
final ValueNotifier<DateTime?> lastClockSync = ValueNotifier<DateTime?>(null);

/// True while a [syncConnectedClock] run is in flight. Surfaced on the Sync
/// buttons so they disable + relabel to "Synchronizing…", and used to coalesce
/// overlapping syncs (rapid taps, or an auto-sync racing a manual one) into one.
final ValueNotifier<bool> clockSyncInProgress = ValueNotifier<bool>(false);

bool _lastSyncLoaded = false;

/// Restores [lastClockSync] from SharedPreferences once per launch.
Future<void> loadLastClockSync() async {
  if (_lastSyncLoaded) return;
  _lastSyncLoaded = true;
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt('lastSyncEpochMs');
  if (ms != null) {
    lastClockSync.value = DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

/// Runs the full phone→clock sync sequence against the connected [device]:
/// handshake (0x04), time (0x01, honouring the Auto Time Sync setting), the
/// alarm table, display settings (0x06), and commit (0x05).
///
/// Shows a success snackbar only when [showSuccess] is true (user-initiated
/// syncs); failures always surface a snackbar. Returns true on success.
Future<bool> syncConnectedClock(
  BuildContext context,
  BluetoothDevice device, {
  bool showSuccess = false,
}) async {
  // Coalesce overlapping syncs: a sync already running wins, and any extra call
  // (a rapid re-tap, or an auto-sync racing a manual one) returns immediately
  // instead of queueing another full sequence behind it.
  if (clockSyncInProgress.value) return false;
  clockSyncInProgress.value = true;

  final repo = context.read<BleRepository>();
  final alarmBloc = context.read<AlarmBloc>();
  final settings = context.read<SettingsBloc>().state;

  try {
    await repo.sendCommand(device, 0x04, const []);
    if (settings.autoTimeSync || showSuccess) {
      // Manual "Sync Now" always pushes time; background syncs respect the
      // Auto Time Sync toggle.
      await repo.sendCommand(device, 0x01, BlePayloads.currentEpochSeconds());
    }
    final alarmSync = Completer<void>();
    alarmBloc.add(SyncAlarmsToDeviceEvent(device, completer: alarmSync));
    await alarmSync.future;
    await repo.sendCommand(
      device,
      0x06,
      BlePayloads.clockSettings(
        autoDim: settings.autoDim,
        sleepStartHour: settings.sleepStartHour,
        sleepStartMinute: settings.sleepStartMinute,
        sleepEndHour: settings.sleepEndHour,
        sleepEndMinute: settings.sleepEndMinute,
      ),
    );
    await repo.sendCommand(device, 0x05, const []);

    lastClockSync.value = DateTime.now();
    unawaited(
      SharedPreferences.getInstance().then(
        (prefs) => prefs.setInt(
          'lastSyncEpochMs',
          lastClockSync.value!.millisecondsSinceEpoch,
        ),
      ),
    );

    if (showSuccess && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Clock sync complete.'),
          backgroundColor: AppColors.success,
        ),
      );
    }
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Clock sync failed. Local changes are still saved.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
    return false;
  } finally {
    clockSyncInProgress.value = false;
  }
}
