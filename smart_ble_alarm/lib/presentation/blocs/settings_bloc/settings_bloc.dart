import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_background.dart';

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
  List<Object?> get props =>
      [themeLight, accentIndex, showSeconds, showDate, showDayOfWeek, dateFormat];
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

/// Chooses the app's ambient background style (see [AppBackgroundStyle]).
class UpdateAppBackgroundEvent extends SettingsEvent {
  final AppBackgroundStyle style;
  const UpdateAppBackgroundEvent(this.style);
  @override
  List<Object?> get props => [style];
}

// --- State ---
class SettingsState extends Equatable {
  final bool is24HourTime;
  final bool defaultQrRequired;
  final String themeString;
  final String accentColorString;
  final bool animationsEnabled;
  final bool autoTimeSync;
  final bool backupNotificationsEnabled;

  // Physical clock display customization (pushed to the clock over 0x06).
  final bool clockThemeLight; // false = dark face, true = light face
  final int clockAccentIndex; // 0 amber, 1 blue, 2 green, 3 violet
  final bool clockShowSeconds;
  final bool clockShowDate; // calendar date on the info line
  final bool clockShowDayOfWeek; // day-of-week on the info line
  final int clockDateFormat; // 0 "MMM D", 1 "D MMM", 2 "MM/DD/YY", 3 "YYYY-MM-DD"

  // Weather corner on the clock face (fetched by the phone, pushed over 0x0C).
  final bool showWeather;
  final bool weatherFahrenheit; // false = °C, true = °F

  // App (phone) ambient background style.
  final String appBackgroundKey;

  const SettingsState({
    this.is24HourTime = false, // false = 12h default
    this.defaultQrRequired = true,
    this.themeString = 'Dark',
    this.accentColorString = 'Ember',
    this.animationsEnabled = true,
    this.autoTimeSync = true,
    this.backupNotificationsEnabled = true,
    this.clockThemeLight = false,
    this.clockAccentIndex = 0,
    this.clockShowSeconds = false,
    this.clockShowDate = true,
    this.clockShowDayOfWeek = true,
    this.clockDateFormat = 0,
    this.showWeather = true,
    this.weatherFahrenheit = false,
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
    bool? clockThemeLight,
    int? clockAccentIndex,
    bool? clockShowSeconds,
    bool? clockShowDate,
    bool? clockShowDayOfWeek,
    int? clockDateFormat,
    bool? showWeather,
    bool? weatherFahrenheit,
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
      clockThemeLight: clockThemeLight ?? this.clockThemeLight,
      clockAccentIndex: clockAccentIndex ?? this.clockAccentIndex,
      clockShowSeconds: clockShowSeconds ?? this.clockShowSeconds,
      clockShowDate: clockShowDate ?? this.clockShowDate,
      clockShowDayOfWeek: clockShowDayOfWeek ?? this.clockShowDayOfWeek,
      clockDateFormat: clockDateFormat ?? this.clockDateFormat,
      showWeather: showWeather ?? this.showWeather,
      weatherFahrenheit: weatherFahrenheit ?? this.weatherFahrenheit,
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
    clockThemeLight,
    clockAccentIndex,
    clockShowSeconds,
    clockShowDate,
    clockShowDayOfWeek,
    clockDateFormat,
    showWeather,
    weatherFahrenheit,
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
    on<UpdateClockDisplayEvent>(_onUpdateClockDisplay);
    on<ToggleShowWeatherEvent>(_onToggleShowWeather);
    on<ToggleWeatherUnitEvent>(_onToggleWeatherUnit);
    on<UpdateAppBackgroundEvent>(_onUpdateAppBackground);
  }

  void _onLoadSettings(LoadSettingsEvent event, Emitter<SettingsState> emit) {
    final bgKey = prefs.getString('appBackground') ?? 'minimal';
    // Prime the global notifier so every GlassBackground paints the saved style
    // from the first frame.
    appBackgroundStyle.value = appBackgroundStyleFromKey(bgKey);
    emit(
      state.copyWith(
        is24HourTime: prefs.getBool('is24HourTime') ?? false,
        defaultQrRequired: prefs.getBool('defaultQrRequired') ?? true,
        themeString: prefs.getString('themeString') ?? 'Dark',
        accentColorString: prefs.getString('accentColorString') ?? 'Ember',
        animationsEnabled: prefs.getBool('animationsEnabled') ?? true,
        autoTimeSync: prefs.getBool('autoTimeSync') ?? true,
        backupNotificationsEnabled:
            prefs.getBool('backupNotificationsEnabled') ?? true,
        clockThemeLight: prefs.getBool('clockThemeLight') ?? false,
        clockAccentIndex: prefs.getInt('clockAccentIndex') ?? 0,
        clockShowSeconds: prefs.getBool('clockShowSeconds') ?? false,
        clockShowDate: prefs.getBool('clockShowDate') ?? true,
        clockShowDayOfWeek: prefs.getBool('clockShowDayOfWeek') ?? true,
        clockDateFormat: prefs.getInt('clockDateFormat') ?? 0,
        showWeather: prefs.getBool('showWeather') ?? true,
        weatherFahrenheit: prefs.getBool('weatherFahrenheit') ?? false,
        appBackgroundKey: bgKey,
      ),
    );
  }

  void _onToggle24HourTime(
    Toggle24HourTimeEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('is24HourTime', event.is24Hour);
    emit(state.copyWith(is24HourTime: event.is24Hour));
  }

  void _onToggleDefaultQrRequired(
    ToggleDefaultQrRequiredEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('defaultQrRequired', event.required);
    emit(state.copyWith(defaultQrRequired: event.required));
  }

  void _onUpdateTheme(
    UpdateThemeEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setString('themeString', event.theme);
    emit(state.copyWith(themeString: event.theme));
  }

  void _onUpdateAccentColor(
    UpdateAccentColorEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setString('accentColorString', event.accentColor);
    emit(state.copyWith(accentColorString: event.accentColor));
  }

  void _onToggleAnimations(
    ToggleAnimationsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('animationsEnabled', event.enabled);
    emit(state.copyWith(animationsEnabled: event.enabled));
  }

  void _onToggleAutoTimeSync(
    ToggleAutoTimeSyncEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('autoTimeSync', event.enabled);
    emit(state.copyWith(autoTimeSync: event.enabled));
  }

  void _onToggleBackupNotifications(
    ToggleBackupNotificationsEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('backupNotificationsEnabled', event.enabled);
    emit(state.copyWith(backupNotificationsEnabled: event.enabled));
  }

  void _onUpdateClockDisplay(
    UpdateClockDisplayEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('clockThemeLight', event.themeLight);
    await prefs.setInt('clockAccentIndex', event.accentIndex);
    await prefs.setBool('clockShowSeconds', event.showSeconds);
    await prefs.setBool('clockShowDate', event.showDate);
    await prefs.setBool('clockShowDayOfWeek', event.showDayOfWeek);
    await prefs.setInt('clockDateFormat', event.dateFormat);
    emit(
      state.copyWith(
        clockThemeLight: event.themeLight,
        clockAccentIndex: event.accentIndex,
        clockShowSeconds: event.showSeconds,
        clockShowDate: event.showDate,
        clockShowDayOfWeek: event.showDayOfWeek,
        clockDateFormat: event.dateFormat,
      ),
    );
  }

  void _onToggleShowWeather(
    ToggleShowWeatherEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('showWeather', event.enabled);
    emit(state.copyWith(showWeather: event.enabled));
  }

  void _onToggleWeatherUnit(
    ToggleWeatherUnitEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('weatherFahrenheit', event.fahrenheit);
    emit(state.copyWith(weatherFahrenheit: event.fahrenheit));
  }

  void _onUpdateAppBackground(
    UpdateAppBackgroundEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setString('appBackground', event.style.storageKey);
    // Drive the global notifier so every visible GlassBackground switches live.
    appBackgroundStyle.value = event.style;
    emit(state.copyWith(appBackgroundKey: event.style.storageKey));
  }
}
