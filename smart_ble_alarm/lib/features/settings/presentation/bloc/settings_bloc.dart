import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/core/theme/app_background.dart';

// --- Events ---
abstract class SettingsEvent extends Equatable {
  const SettingsEvent();
  @override
  List<Object?> get props => [];
}

class LoadSettingsEvent extends SettingsEvent {}

class Toggle24HourTimeEvent extends SettingsEvent {
  final bool is24Hour;
  const Toggle24HourTimeEvent(this.is24Hour);
  @override
  List<Object?> get props => [is24Hour];
}

class ToggleDefaultQrRequiredEvent extends SettingsEvent {
  final bool required;
  const ToggleDefaultQrRequiredEvent(this.required);
  @override
  List<Object?> get props => [required];
}

class UpdateThemeEvent extends SettingsEvent {
  final String theme;
  const UpdateThemeEvent(this.theme);
  @override
  List<Object?> get props => [theme];
}

class UpdateAccentColorEvent extends SettingsEvent {
  final String accentColor;
  const UpdateAccentColorEvent(this.accentColor);
  @override
  List<Object?> get props => [accentColor];
}

class ToggleAnimationsEvent extends SettingsEvent {
  final bool enabled;
  const ToggleAnimationsEvent(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

class ToggleAutoTimeSyncEvent extends SettingsEvent {
  final bool enabled;
  const ToggleAutoTimeSyncEvent(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

class ToggleBackupNotificationsEvent extends SettingsEvent {
  final bool enabled;
  const ToggleBackupNotificationsEvent(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

class ToggleEveningReminderEvent extends SettingsEvent {
  final bool enabled;
  const ToggleEveningReminderEvent(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

/// Updates the physical clock's display customization (theme/accent/seconds/
/// date). These are pushed to the clock over BLE (0x06); the 24-hour format
/// rides along from [is24HourTime].
class UpdateClockDisplayEvent extends SettingsEvent {
  final bool themeLight;
  final int accentIndex;
  final bool showSeconds;
  final bool showDate;
  final bool showDayOfWeek;
  final int dateFormat;
  const UpdateClockDisplayEvent({
    required this.themeLight,
    required this.accentIndex,
    required this.showSeconds,
    required this.showDate,
    required this.showDayOfWeek,
    required this.dateFormat,
  });
  @override
  List<Object?> get props => [
    themeLight,
    accentIndex,
    showSeconds,
    showDate,
    showDayOfWeek,
    dateFormat,
  ];
}

/// Updates the clock's scheduled display-sleep window (command 0x0D). During the
/// window the clock blanks its panel so a dark room stays dark. Times are
/// minutes-of-day (0..1439); the window may wrap past midnight.
class UpdateClockSleepEvent extends SettingsEvent {
  final bool enabled;
  final int startMinutes;
  final int endMinutes;
  const UpdateClockSleepEvent({
    required this.enabled,
    required this.startMinutes,
    required this.endMinutes,
  });
  @override
  List<Object?> get props => [enabled, startMinutes, endMinutes];
}

/// Restores the physical clock's display controls to the first-run WakeGuard
/// defaults. This only resets display-related settings: it does not touch
/// alarms, account data, pairing, notifications, or app-wide appearance.
class ResetClockDisplayEvent extends SettingsEvent {
  const ResetClockDisplayEvent();
}

/// Turns the clock's weather corner on/off. When off the app pushes a "hide"
/// frame (0x0C `[0,0xFF]`) so the clock blanks it.
class ToggleShowWeatherEvent extends SettingsEvent {
  final bool enabled;
  const ToggleShowWeatherEvent(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

/// Chooses the unit the clock's weather is shown in. The app converts before
/// sending; the clock is unit-agnostic (just prints the number + a degree ring).
class ToggleWeatherUnitEvent extends SettingsEvent {
  final bool fahrenheit;
  const ToggleWeatherUnitEvent(this.fahrenheit);
  @override
  List<Object?> get props => [fahrenheit];
}

/// Turns the "Ring on this phone" engine on/off. When on, this phone rings the
/// alarm itself (foreground, best-effort) and runs the wake challenge to
/// dismiss, so an alarm still fires without the hardware clock. See
/// [SettingsState.phoneAlarmEnabled] and `PhoneAlarmRinger`.
class TogglePhoneAlarmEvent extends SettingsEvent {
  final bool enabled;
  const TogglePhoneAlarmEvent(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

/// When on, the iOS keep-alive ring engine only runs while the phone is charging
/// (it prevents overnight battery drain; off-charger falls back to notifications).
class TogglePhoneAlarmChargingEvent extends SettingsEvent {
  final bool requireCharging;
  const TogglePhoneAlarmChargingEvent(this.requireCharging);
  @override
  List<Object?> get props => [requireCharging];
}

/// Turns "Dedicated Clock" mode on/off. When on, this device is treated as a
/// standby bedside WakeGuard clock: the app boots straight into the full-screen
/// clock face (see [SettingsState.dedicatedClockEnabled]) and rings in the
/// morning while it stays open on a charger. Distinct from [phoneAlarmEnabled],
/// which is a backup ringer for your *primary* phone and shows no clock face.
class ToggleDedicatedClockEvent extends SettingsEvent {
  final bool enabled;
  const ToggleDedicatedClockEvent(this.enabled);
  @override
  List<Object?> get props => [enabled];
}

/// Chooses the app's ambient background style (see [AppBackgroundStyle]).
class UpdateAppBackgroundEvent extends SettingsEvent {
  final AppBackgroundStyle style;
  const UpdateAppBackgroundEvent(this.style);
  @override
  List<Object?> get props => [style];
}

// --- State ---
class SettingsState extends Equatable {
  static const defaultIs24HourTime = false;
  static const defaultClockThemeLight = false;
  static const defaultClockAccentIndex = 0;
  static const defaultClockShowSeconds = false;
  static const defaultClockShowDate = true;
  static const defaultClockShowDayOfWeek = true;
  static const defaultClockDateFormat = 0;
  static const defaultClockSleepEnabled = false;
  static const defaultClockSleepStartMinutes = 22 * 60;
  static const defaultClockSleepEndMinutes = 7 * 60;
  static const defaultShowWeather = true;
  static const defaultWeatherFahrenheit = false;

  final bool is24HourTime;
  final bool defaultQrRequired;
  final String themeString;
  final String accentColorString;
  final bool animationsEnabled;
  final bool autoTimeSync;
  final bool backupNotificationsEnabled;
  final bool eveningReminderEnabled;

  // Physical clock display customization (pushed to the clock over 0x06).
  final bool clockThemeLight; // false = dark face, true = light face
  final int clockAccentIndex; // 0 amber, 1 blue, 2 green, 3 violet
  final bool clockShowSeconds;
  final bool clockShowDate; // calendar date on the info line
  final bool clockShowDayOfWeek; // day-of-week on the info line
  final int
  clockDateFormat; // 0 "MMM D", 1 "D MMM", 2 "MM/DD/YY", 3 "YYYY-MM-DD"

  // Scheduled display sleep (pushed to the clock over 0x0D). During the window the
  // clock blanks its panel; times are minutes-of-day and may wrap past midnight.
  final bool clockSleepEnabled;
  final int clockSleepStartMinutes; // minutes-of-day the panel blanks
  final int clockSleepEndMinutes; // minutes-of-day it wakes

  // Weather corner on the clock face (fetched by the phone, pushed over 0x0C).
  final bool showWeather;
  final bool weatherFahrenheit; // false = °C, true = °F

  // "Ring on this phone": the app rings the alarm itself (foreground,
  // best-effort) so an alarm fires without the hardware clock. See
  // `PhoneAlarmRinger`.
  final bool phoneAlarmEnabled;
  // Retained for back-compat with persisted prefs; not surfaced in the UI (the
  // foreground engine has no keep-alive to gate on charging).
  final bool phoneAlarmRequireCharging;

  // Dedicated Clock mode: this device is a standby bedside clock. Drives the
  // top-precedence route to DedicatedClockScreen in main.dart.
  final bool dedicatedClockEnabled;

  // App (phone) ambient background style.
  final String appBackgroundKey;

  const SettingsState({
    this.is24HourTime = defaultIs24HourTime, // false = 12h default
    this.defaultQrRequired = true,
    this.themeString = 'Dark',
    this.accentColorString = 'Ember',
    this.animationsEnabled = true,
    this.autoTimeSync = true,
    this.backupNotificationsEnabled = true,
    this.eveningReminderEnabled = false,
    this.clockThemeLight = defaultClockThemeLight,
    this.clockAccentIndex = defaultClockAccentIndex,
    this.clockShowSeconds = defaultClockShowSeconds,
    this.clockShowDate = defaultClockShowDate,
    this.clockShowDayOfWeek = defaultClockShowDayOfWeek,
    this.clockDateFormat = defaultClockDateFormat,
    this.clockSleepEnabled = defaultClockSleepEnabled,
    this.clockSleepStartMinutes = defaultClockSleepStartMinutes, // 22:00
    this.clockSleepEndMinutes = defaultClockSleepEndMinutes, // 07:00
    this.showWeather = defaultShowWeather,
    this.weatherFahrenheit = defaultWeatherFahrenheit,
    this.phoneAlarmEnabled = false,
    this.phoneAlarmRequireCharging = true,
    this.dedicatedClockEnabled = false,
    this.appBackgroundKey = 'minimal',
  });

  AppBackgroundStyle get appBackground =>
      appBackgroundStyleFromKey(appBackgroundKey);

  SettingsState copyWith({
    bool? is24HourTime,
    bool? defaultQrRequired,
    String? themeString,
    String? accentColorString,
    bool? animationsEnabled,
    bool? autoTimeSync,
    bool? backupNotificationsEnabled,
    bool? eveningReminderEnabled,
    bool? clockThemeLight,
    int? clockAccentIndex,
    bool? clockShowSeconds,
    bool? clockShowDate,
    bool? clockShowDayOfWeek,
    int? clockDateFormat,
    bool? clockSleepEnabled,
    int? clockSleepStartMinutes,
    int? clockSleepEndMinutes,
    bool? showWeather,
    bool? weatherFahrenheit,
    bool? phoneAlarmEnabled,
    bool? phoneAlarmRequireCharging,
    bool? dedicatedClockEnabled,
    String? appBackgroundKey,
  }) {
    return SettingsState(
      is24HourTime: is24HourTime ?? this.is24HourTime,
      defaultQrRequired: defaultQrRequired ?? this.defaultQrRequired,
      themeString: themeString ?? this.themeString,
      accentColorString: accentColorString ?? this.accentColorString,
      animationsEnabled: animationsEnabled ?? this.animationsEnabled,
      autoTimeSync: autoTimeSync ?? this.autoTimeSync,
      backupNotificationsEnabled:
          backupNotificationsEnabled ?? this.backupNotificationsEnabled,
      eveningReminderEnabled:
          eveningReminderEnabled ?? this.eveningReminderEnabled,
      clockThemeLight: clockThemeLight ?? this.clockThemeLight,
      clockAccentIndex: clockAccentIndex ?? this.clockAccentIndex,
      clockShowSeconds: clockShowSeconds ?? this.clockShowSeconds,
      clockShowDate: clockShowDate ?? this.clockShowDate,
      clockShowDayOfWeek: clockShowDayOfWeek ?? this.clockShowDayOfWeek,
      clockDateFormat: clockDateFormat ?? this.clockDateFormat,
      clockSleepEnabled: clockSleepEnabled ?? this.clockSleepEnabled,
      clockSleepStartMinutes:
          clockSleepStartMinutes ?? this.clockSleepStartMinutes,
      clockSleepEndMinutes: clockSleepEndMinutes ?? this.clockSleepEndMinutes,
      showWeather: showWeather ?? this.showWeather,
      weatherFahrenheit: weatherFahrenheit ?? this.weatherFahrenheit,
      phoneAlarmEnabled: phoneAlarmEnabled ?? this.phoneAlarmEnabled,
      phoneAlarmRequireCharging:
          phoneAlarmRequireCharging ?? this.phoneAlarmRequireCharging,
      dedicatedClockEnabled:
          dedicatedClockEnabled ?? this.dedicatedClockEnabled,
      appBackgroundKey: appBackgroundKey ?? this.appBackgroundKey,
    );
  }

  @override
  List<Object?> get props => [
    is24HourTime,
    defaultQrRequired,
    themeString,
    accentColorString,
    animationsEnabled,
    autoTimeSync,
    backupNotificationsEnabled,
    eveningReminderEnabled,
    clockThemeLight,
    clockAccentIndex,
    clockShowSeconds,
    clockShowDate,
    clockShowDayOfWeek,
    clockDateFormat,
    clockSleepEnabled,
    clockSleepStartMinutes,
    clockSleepEndMinutes,
    showWeather,
    weatherFahrenheit,
    phoneAlarmEnabled,
    phoneAlarmRequireCharging,
    dedicatedClockEnabled,
    appBackgroundKey,
  ];
}

// --- Bloc ---
class SettingsBloc extends Bloc<SettingsEvent, SettingsState> {
  final SharedPreferences prefs;

  SettingsBloc({required this.prefs}) : super(const SettingsState()) {
    on<LoadSettingsEvent>(_onLoadSettings);
    on<Toggle24HourTimeEvent>(_onToggle24HourTime);
    on<ToggleDefaultQrRequiredEvent>(_onToggleDefaultQrRequired);
    on<UpdateThemeEvent>(_onUpdateTheme);
    on<UpdateAccentColorEvent>(_onUpdateAccentColor);
    on<ToggleAnimationsEvent>(_onToggleAnimations);
    on<ToggleAutoTimeSyncEvent>(_onToggleAutoTimeSync);
    on<ToggleBackupNotificationsEvent>(_onToggleBackupNotifications);
    on<ToggleEveningReminderEvent>(_onToggleEveningReminder);
    on<UpdateClockDisplayEvent>(_onUpdateClockDisplay);
    on<UpdateClockSleepEvent>(_onUpdateClockSleep);
    on<ResetClockDisplayEvent>(_onResetClockDisplay);
    on<ToggleShowWeatherEvent>(_onToggleShowWeather);
    on<ToggleWeatherUnitEvent>(_onToggleWeatherUnit);
    on<TogglePhoneAlarmEvent>(_onTogglePhoneAlarm);
    on<TogglePhoneAlarmChargingEvent>(_onTogglePhoneAlarmCharging);
    on<ToggleDedicatedClockEvent>(_onToggleDedicatedClock);
    on<UpdateAppBackgroundEvent>(_onUpdateAppBackground);
  }

  static int _clockAccentIndex(int value) => value.clamp(0, 3).toInt();
  static int _clockDateFormat(int value) => value.clamp(0, 3).toInt();

  void _onLoadSettings(LoadSettingsEvent event, Emitter<SettingsState> emit) {
    final bgKey = prefs.getString('appBackground') ?? 'minimal';
    final clockAccentIndex = _clockAccentIndex(
      prefs.getInt('clockAccentIndex') ?? SettingsState.defaultClockAccentIndex,
    );
    final clockDateFormat = _clockDateFormat(
      prefs.getInt('clockDateFormat') ?? SettingsState.defaultClockDateFormat,
    );
    // Prime the global notifier so every GlassBackground paints the saved style
    // from the first frame.
    appBackgroundStyle.value = appBackgroundStyleFromKey(bgKey);
    emit(
      state.copyWith(
        is24HourTime:
            prefs.getBool('is24HourTime') ?? SettingsState.defaultIs24HourTime,
        defaultQrRequired: prefs.getBool('defaultQrRequired') ?? true,
        themeString: prefs.getString('themeString') ?? 'Dark',
        accentColorString: prefs.getString('accentColorString') ?? 'Ember',
        animationsEnabled: prefs.getBool('animationsEnabled') ?? true,
        autoTimeSync: prefs.getBool('autoTimeSync') ?? true,
        backupNotificationsEnabled:
            prefs.getBool('backupNotificationsEnabled') ?? true,
        eveningReminderEnabled:
            prefs.getBool('eveningReminderEnabled') ?? false,
        clockThemeLight:
            prefs.getBool('clockThemeLight') ??
            SettingsState.defaultClockThemeLight,
        clockAccentIndex: clockAccentIndex,
        clockShowSeconds:
            prefs.getBool('clockShowSeconds') ??
            SettingsState.defaultClockShowSeconds,
        clockShowDate:
            prefs.getBool('clockShowDate') ??
            SettingsState.defaultClockShowDate,
        clockShowDayOfWeek:
            prefs.getBool('clockShowDayOfWeek') ??
            SettingsState.defaultClockShowDayOfWeek,
        clockDateFormat: clockDateFormat,
        clockSleepEnabled:
            prefs.getBool('clockSleepEnabled') ??
            SettingsState.defaultClockSleepEnabled,
        clockSleepStartMinutes:
            prefs.getInt('clockSleepStart') ??
            SettingsState.defaultClockSleepStartMinutes,
        clockSleepEndMinutes:
            prefs.getInt('clockSleepEnd') ??
            SettingsState.defaultClockSleepEndMinutes,
        showWeather:
            prefs.getBool('showWeather') ?? SettingsState.defaultShowWeather,
        weatherFahrenheit:
            prefs.getBool('weatherFahrenheit') ??
            SettingsState.defaultWeatherFahrenheit,
        phoneAlarmEnabled: prefs.getBool('phoneAlarmEnabled') ?? false,
        phoneAlarmRequireCharging:
            prefs.getBool('phoneAlarmRequireCharging') ?? true,
        dedicatedClockEnabled: prefs.getBool('dedicatedClockEnabled') ?? false,
        appBackgroundKey: bgKey,
      ),
    );
  }

  Future<void> _onToggle24HourTime(
    Toggle24HourTimeEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('is24HourTime', event.is24Hour);
    emit(state.copyWith(is24HourTime: event.is24Hour));
  }

  Future<void> _onToggleDefaultQrRequired(
    ToggleDefaultQrRequiredEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('defaultQrRequired', event.required);
    emit(state.copyWith(defaultQrRequired: event.required));
  }

  Future<void> _onUpdateTheme(
    UpdateThemeEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setString('themeString', event.theme);
    emit(state.copyWith(themeString: event.theme));
  }

  Future<void> _onUpdateAccentColor(
    UpdateAccentColorEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setString('accentColorString', event.accentColor);
    emit(state.copyWith(accentColorString: event.accentColor));
  }

  Future<void> _onToggleAnimations(
    ToggleAnimationsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('animationsEnabled', event.enabled);
    emit(state.copyWith(animationsEnabled: event.enabled));
  }

  Future<void> _onToggleAutoTimeSync(
    ToggleAutoTimeSyncEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('autoTimeSync', event.enabled);
    emit(state.copyWith(autoTimeSync: event.enabled));
  }

  Future<void> _onToggleBackupNotifications(
    ToggleBackupNotificationsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('backupNotificationsEnabled', event.enabled);
    emit(state.copyWith(backupNotificationsEnabled: event.enabled));
  }

  Future<void> _onToggleEveningReminder(
    ToggleEveningReminderEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('eveningReminderEnabled', event.enabled);
    emit(state.copyWith(eveningReminderEnabled: event.enabled));
  }

  Future<void> _onUpdateClockDisplay(
    UpdateClockDisplayEvent event,
    Emitter<SettingsState> emit,
  ) async {
    final accentIndex = _clockAccentIndex(event.accentIndex);
    final dateFormat = _clockDateFormat(event.dateFormat);
    await prefs.setBool('clockThemeLight', event.themeLight);
    await prefs.setInt('clockAccentIndex', accentIndex);
    await prefs.setBool('clockShowSeconds', event.showSeconds);
    await prefs.setBool('clockShowDate', event.showDate);
    await prefs.setBool('clockShowDayOfWeek', event.showDayOfWeek);
    await prefs.setInt('clockDateFormat', dateFormat);
    emit(
      state.copyWith(
        clockThemeLight: event.themeLight,
        clockAccentIndex: accentIndex,
        clockShowSeconds: event.showSeconds,
        clockShowDate: event.showDate,
        clockShowDayOfWeek: event.showDayOfWeek,
        clockDateFormat: dateFormat,
      ),
    );
  }

  Future<void> _onUpdateClockSleep(
    UpdateClockSleepEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('clockSleepEnabled', event.enabled);
    await prefs.setInt('clockSleepStart', event.startMinutes);
    await prefs.setInt('clockSleepEnd', event.endMinutes);
    emit(
      state.copyWith(
        clockSleepEnabled: event.enabled,
        clockSleepStartMinutes: event.startMinutes,
        clockSleepEndMinutes: event.endMinutes,
      ),
    );
  }

  Future<void> _onResetClockDisplay(
    ResetClockDisplayEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('is24HourTime', SettingsState.defaultIs24HourTime);
    await prefs.setBool(
      'clockThemeLight',
      SettingsState.defaultClockThemeLight,
    );
    await prefs.setInt(
      'clockAccentIndex',
      SettingsState.defaultClockAccentIndex,
    );
    await prefs.setBool(
      'clockShowSeconds',
      SettingsState.defaultClockShowSeconds,
    );
    await prefs.setBool('clockShowDate', SettingsState.defaultClockShowDate);
    await prefs.setBool(
      'clockShowDayOfWeek',
      SettingsState.defaultClockShowDayOfWeek,
    );
    await prefs.setInt('clockDateFormat', SettingsState.defaultClockDateFormat);
    await prefs.setBool(
      'clockSleepEnabled',
      SettingsState.defaultClockSleepEnabled,
    );
    await prefs.setInt(
      'clockSleepStart',
      SettingsState.defaultClockSleepStartMinutes,
    );
    await prefs.setInt(
      'clockSleepEnd',
      SettingsState.defaultClockSleepEndMinutes,
    );
    await prefs.setBool('showWeather', SettingsState.defaultShowWeather);
    await prefs.setBool(
      'weatherFahrenheit',
      SettingsState.defaultWeatherFahrenheit,
    );

    emit(
      state.copyWith(
        is24HourTime: SettingsState.defaultIs24HourTime,
        clockThemeLight: SettingsState.defaultClockThemeLight,
        clockAccentIndex: SettingsState.defaultClockAccentIndex,
        clockShowSeconds: SettingsState.defaultClockShowSeconds,
        clockShowDate: SettingsState.defaultClockShowDate,
        clockShowDayOfWeek: SettingsState.defaultClockShowDayOfWeek,
        clockDateFormat: SettingsState.defaultClockDateFormat,
        clockSleepEnabled: SettingsState.defaultClockSleepEnabled,
        clockSleepStartMinutes: SettingsState.defaultClockSleepStartMinutes,
        clockSleepEndMinutes: SettingsState.defaultClockSleepEndMinutes,
        showWeather: SettingsState.defaultShowWeather,
        weatherFahrenheit: SettingsState.defaultWeatherFahrenheit,
      ),
    );
  }

  Future<void> _onToggleShowWeather(
    ToggleShowWeatherEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('showWeather', event.enabled);
    emit(state.copyWith(showWeather: event.enabled));
  }

  Future<void> _onToggleWeatherUnit(
    ToggleWeatherUnitEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('weatherFahrenheit', event.fahrenheit);
    emit(state.copyWith(weatherFahrenheit: event.fahrenheit));
  }

  Future<void> _onTogglePhoneAlarm(
    TogglePhoneAlarmEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('phoneAlarmEnabled', event.enabled);
    emit(state.copyWith(phoneAlarmEnabled: event.enabled));
  }

  Future<void> _onTogglePhoneAlarmCharging(
    TogglePhoneAlarmChargingEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('phoneAlarmRequireCharging', event.requireCharging);
    emit(state.copyWith(phoneAlarmRequireCharging: event.requireCharging));
  }

  Future<void> _onToggleDedicatedClock(
    ToggleDedicatedClockEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('dedicatedClockEnabled', event.enabled);
    emit(state.copyWith(dedicatedClockEnabled: event.enabled));
  }

  Future<void> _onUpdateAppBackground(
    UpdateAppBackgroundEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setString('appBackground', event.style.storageKey);
    // Drive the global notifier so every visible GlassBackground switches live.
    appBackgroundStyle.value = event.style;
    emit(state.copyWith(appBackgroundKey: event.style.storageKey));
  }
}
