import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/datasources/weather_datasource.dart';
import '../../domain/repositories/ble_repository.dart';
import '../../presentation/blocs/alarm_bloc/alarm_bloc.dart';
import '../../presentation/blocs/settings_bloc/settings_bloc.dart';
import '../ui/app_snackbar.dart';
import 'ble_payloads.dart';

const WeatherDatasource _weatherSource = WeatherDatasource();

/// Best-effort weather push (command 0x0C). The clock has no network, so the
/// phone fetches the current conditions and forwards them. Never throws and never
/// blocks a sync's result: callers fire it with `unawaited(...)`. When the user
/// has weather turned off it sends the "hide" frame so the clock blanks the corner.
Future<void> pushWeatherToClock(
  BleRepository repo,
  BluetoothDevice device,
  SettingsState settings,
) async {
  try {
    if (!settings.showWeather) {
      await repo.sendCommand(device, 0x0C, BlePayloads.weatherHidden());
      return;
    }
    final reading =
        await _weatherSource.fetch(fahrenheit: settings.weatherFahrenheit);
    if (reading == null) return; // offline / lookup failed — leave last value
    await repo.sendCommand(
      device,
      0x0C,
      BlePayloads.weather(temp: reading.temp, conditionCode: reading.code),
    );
  } catch (_) {
    // Weather is non-critical; a failure must never affect the clock or app.
  }
}

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
/// [showSuccess] marks a user-initiated sync (the "Sync Now" buttons): it shows
/// a success card on completion AND the failure card if every attempt fails.
/// Background/auto syncs (on connect, on a resumed link) pass `false` and are
/// SILENT on failure — the connectivity banner already conveys link state and
/// the sync auto-retries, so a red card there just read as a spurious "bug".
///
/// A freshly-established HM-10 link is flaky for the first few hundred ms, so a
/// failed sequence is retried once after a short settle delay before it counts
/// as a real failure. Returns true on success.
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

  // Capture blocs/repo up front so the retry loop below never touches an
  // unmounted BuildContext for lookups (only .mounted-guarded UI uses it).
  final repo = context.read<BleRepository>();
  final alarmBloc = context.read<AlarmBloc>();
  final settingsBloc = context.read<SettingsBloc>();
  final bool userInitiated = showSuccess;

  // One retry: the common failure is a write that lands before the link has
  // settled right after connecting, which succeeds on a second pass.
  const int maxAttempts = 2;

  try {
    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final settings = settingsBloc.state;
        await repo.sendCommand(device, 0x04, const []);
        if (settings.autoTimeSync || userInitiated) {
          // Manual "Sync Now" always pushes time; background syncs respect the
          // Auto Time Sync toggle.
          await repo.sendCommand(
            device,
            0x01,
            BlePayloads.currentEpochSeconds(),
          );
        }
        final alarmSync = Completer<void>();
        alarmBloc.add(SyncAlarmsToDeviceEvent(device, completer: alarmSync));
        await alarmSync.future;
        // Push the clock-face display settings (theme/accent/seconds/date + the
        // 24-hour format) so the physical clock matches the app.
        await repo.sendCommand(
          device,
          0x06,
          BlePayloads.clockDisplaySettings(
            use24h: settings.is24HourTime,
            showSeconds: settings.clockShowSeconds,
            showDate: settings.clockShowDate,
            showDayOfWeek: settings.clockShowDayOfWeek,
            dateFormat: settings.clockDateFormat,
            theme: settings.clockThemeLight ? 1 : 0,
            accent: settings.clockAccentIndex,
          ),
        );
        // Scheduled display-sleep window (0x0D). RAM-only on the clock, so it rides
        // every sync alongside the display settings to survive a clock reboot.
        await repo.sendCommand(
          device,
          0x0D,
          BlePayloads.clockSleepSchedule(
            enabled: settings.clockSleepEnabled,
            startHour: settings.clockSleepStartMinutes ~/ 60,
            startMinute: settings.clockSleepStartMinutes % 60,
            endHour: settings.clockSleepEndMinutes ~/ 60,
            endMinute: settings.clockSleepEndMinutes % 60,
          ),
        );
        await repo.sendCommand(device, 0x05, const []);

        // Weather rides along after the batch commits — best-effort and
        // unawaited so its network fetch can't delay or fail the sync result.
        unawaited(pushWeatherToClock(repo, device, settings));

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
          showAppSnackBar(
            context,
            'Clock sync complete.',
            type: AppSnackType.success,
          );
        }
        return true;
      } catch (_) {
        if (attempt < maxAttempts) {
          // Let the link settle, then try the whole sequence once more.
          await Future.delayed(const Duration(milliseconds: 600));
          continue;
        }
        // Only user-initiated syncs surface a failure card; auto syncs stay
        // silent (the banner covers link state, and the next change/reconnect
        // re-syncs).
        if (userInitiated && context.mounted) {
          showAppSnackBar(
            context,
            'Clock sync failed. Local changes are still saved.',
            type: AppSnackType.error,
          );
        }
        return false;
      }
    }
    return false;
  } finally {
    clockSyncInProgress.value = false;
  }
}
