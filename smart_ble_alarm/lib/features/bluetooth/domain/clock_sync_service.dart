import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/core/ble/ble_payloads.dart';
import 'package:smart_ble_alarm/core/observability/app_analytics.dart';
import 'package:smart_ble_alarm/core/observability/crash_reporting_service.dart';
import 'package:smart_ble_alarm/data/datasources/weather_datasource.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';

typedef ClockSyncSettingsProvider = SettingsState Function();
typedef ClockSyncMessage = void Function(String message);

final ValueNotifier<DateTime?> lastClockSync = ValueNotifier<DateTime?>(null);
final ValueNotifier<bool> clockSyncInProgress = ValueNotifier<bool>(false);

bool _lastSyncLoaded = false;

Future<void> loadLastClockSync() async {
  if (_lastSyncLoaded) return;
  _lastSyncLoaded = true;
  final prefs = await SharedPreferences.getInstance();
  final ms = prefs.getInt('lastSyncEpochMs');
  if (ms != null) {
    lastClockSync.value = DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

final ClockSyncService clockSyncService = ClockSyncService();

class ClockSyncService {
  ClockSyncService({WeatherDatasource? weatherSource})
    : _weatherSource = weatherSource ?? const WeatherDatasource();

  final WeatherDatasource _weatherSource;

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
      final reading = await _weatherSource.fetch(
        fahrenheit: settings.weatherFahrenheit,
      );
      if (reading == null) return;
      await repo.sendCommand(
        device,
        0x0C,
        BlePayloads.weather(temp: reading.temp, conditionCode: reading.code),
      );
    } catch (error, stackTrace) {
      await CrashReportingService.recordError(
        error,
        stackTrace,
        reason: 'weather_clock_push_failed',
      );
    }
  }

  Future<bool> syncConnectedClock({
    required BleRepository repo,
    required AlarmBloc alarmBloc,
    required ClockSyncSettingsProvider settingsProvider,
    required BluetoothDevice device,
    bool userInitiated = false,
    ClockSyncMessage? onSuccess,
    ClockSyncMessage? onFailure,
  }) async {
    if (clockSyncInProgress.value) return false;
    clockSyncInProgress.value = true;

    const maxAttempts = 2;

    try {
      for (int attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          final settings = settingsProvider();
          await repo.sendCommand(device, 0x04, const []);
          if (settings.autoTimeSync || userInitiated) {
            await repo.sendCommand(
              device,
              0x01,
              BlePayloads.currentEpochSeconds(),
            );
          }

          final alarmSync = Completer<void>();
          alarmBloc.add(SyncAlarmsToDeviceEvent(device, completer: alarmSync));
          await alarmSync.future;

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

          unawaited(pushWeatherToClock(repo, device, settings));

          final now = DateTime.now();
          lastClockSync.value = now;
          unawaited(
            SharedPreferences.getInstance().then(
              (prefs) =>
                  prefs.setInt('lastSyncEpochMs', now.millisecondsSinceEpoch),
            ),
          );

          if (userInitiated) onSuccess?.call('Clock sync complete.');
          return true;
        } catch (error, stackTrace) {
          if (attempt < maxAttempts) {
            await Future<void>.delayed(const Duration(milliseconds: 600));
            continue;
          }
          unawaited(
            AppAnalytics.instance.alarmSyncFailed(source: 'clock_sync'),
          );
          await CrashReportingService.recordError(
            error,
            stackTrace,
            reason: 'clock_sync_failed',
          );
          if (userInitiated) {
            onFailure?.call(
              'Clock sync failed. Local changes are still saved.',
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
}
