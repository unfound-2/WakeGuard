import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';

void main() {
  group('SettingsBloc', () {
    test(
      'reset clock display restores and persists first-run defaults',
      () async {
        SharedPreferences.setMockInitialValues({
          'is24HourTime': true,
          'clockThemeLight': true,
          'clockAccentIndex': 3,
          'clockShowSeconds': true,
          'clockShowDate': false,
          'clockShowDayOfWeek': false,
          'clockDateFormat': 3,
          'clockSleepEnabled': true,
          'clockSleepStart': 23 * 60,
          'clockSleepEnd': 8 * 60,
          'showWeather': false,
          'weatherFahrenheit': true,
        });

        final prefs = await SharedPreferences.getInstance();
        final bloc = SettingsBloc(prefs: prefs)..add(LoadSettingsEvent());
        await bloc.stream.first;

        bloc.add(const ResetClockDisplayEvent());
        final reset = await bloc.stream.firstWhere(
          (state) =>
              state.clockAccentIndex == SettingsState.defaultClockAccentIndex &&
              state.clockShowDate == SettingsState.defaultClockShowDate,
        );

        expect(reset.is24HourTime, SettingsState.defaultIs24HourTime);
        expect(reset.clockThemeLight, SettingsState.defaultClockThemeLight);
        expect(reset.clockAccentIndex, SettingsState.defaultClockAccentIndex);
        expect(reset.clockShowSeconds, SettingsState.defaultClockShowSeconds);
        expect(reset.clockShowDate, SettingsState.defaultClockShowDate);
        expect(
          reset.clockShowDayOfWeek,
          SettingsState.defaultClockShowDayOfWeek,
        );
        expect(reset.clockDateFormat, SettingsState.defaultClockDateFormat);
        expect(reset.clockSleepEnabled, SettingsState.defaultClockSleepEnabled);
        expect(
          reset.clockSleepStartMinutes,
          SettingsState.defaultClockSleepStartMinutes,
        );
        expect(
          reset.clockSleepEndMinutes,
          SettingsState.defaultClockSleepEndMinutes,
        );
        expect(reset.showWeather, SettingsState.defaultShowWeather);
        expect(reset.weatherFahrenheit, SettingsState.defaultWeatherFahrenheit);

        expect(
          prefs.getInt('clockAccentIndex'),
          SettingsState.defaultClockAccentIndex,
        );
        expect(
          prefs.getBool('clockSleepEnabled'),
          SettingsState.defaultClockSleepEnabled,
        );
        expect(prefs.getBool('showWeather'), SettingsState.defaultShowWeather);

        await bloc.close();
      },
    );
  });
}
