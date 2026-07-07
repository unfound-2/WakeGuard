import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class UpdateClockConfigEvent extends SettingsEvent {
  final bool autoDim;
  final int sleepStartHour;
  final int sleepStartMinute;
  final int sleepEndHour;
  final int sleepEndMinute;
  const UpdateClockConfigEvent(
    this.autoDim,
    this.sleepStartHour,
    this.sleepStartMinute,
    this.sleepEndHour,
    this.sleepEndMinute,
  );
  @override
  List<Object?> get props => [
    autoDim,
    sleepStartHour,
    sleepStartMinute,
    sleepEndHour,
    sleepEndMinute,
  ];
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

  // Clock specific settings
  final bool autoDim;
  final int sleepStartHour;
  final int sleepStartMinute;
  final int sleepEndHour;
  final int sleepEndMinute;

  const SettingsState({
    this.is24HourTime = false, // false = 12h default
    this.defaultQrRequired = true,
    this.themeString = 'Dark',
    this.accentColorString = 'Ember',
    this.animationsEnabled = true,
    this.autoTimeSync = true,
    this.backupNotificationsEnabled = true,
    this.autoDim = true,
    this.sleepStartHour = 22,
    this.sleepStartMinute = 0,
    this.sleepEndHour = 6,
    this.sleepEndMinute = 0,
  });

  SettingsState copyWith({
    bool? is24HourTime,
    bool? defaultQrRequired,
    String? themeString,
    String? accentColorString,
    bool? animationsEnabled,
    bool? autoTimeSync,
    bool? backupNotificationsEnabled,
    bool? autoDim,
    int? sleepStartHour,
    int? sleepStartMinute,
    int? sleepEndHour,
    int? sleepEndMinute,
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
      autoDim: autoDim ?? this.autoDim,
      sleepStartHour: sleepStartHour ?? this.sleepStartHour,
      sleepStartMinute: sleepStartMinute ?? this.sleepStartMinute,
      sleepEndHour: sleepEndHour ?? this.sleepEndHour,
      sleepEndMinute: sleepEndMinute ?? this.sleepEndMinute,
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
    autoDim,
    sleepStartHour,
    sleepStartMinute,
    sleepEndHour,
    sleepEndMinute,
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
    on<UpdateClockConfigEvent>(_onUpdateClockConfig);
  }

  void _onLoadSettings(LoadSettingsEvent event, Emitter<SettingsState> emit) {
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
        autoDim: prefs.getBool('autoDim') ?? true,
        sleepStartHour: prefs.getInt('sleepStartHour') ?? 22,
        sleepStartMinute: prefs.getInt('sleepStartMinute') ?? 0,
        sleepEndHour: prefs.getInt('sleepEndHour') ?? 6,
        sleepEndMinute: prefs.getInt('sleepEndMinute') ?? 0,
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

  void _onUpdateClockConfig(
    UpdateClockConfigEvent event,
    Emitter<SettingsState> emit,
  ) async {
    await prefs.setBool('autoDim', event.autoDim);
    await prefs.setInt('sleepStartHour', event.sleepStartHour);
    await prefs.setInt('sleepStartMinute', event.sleepStartMinute);
    await prefs.setInt('sleepEndHour', event.sleepEndHour);
    await prefs.setInt('sleepEndMinute', event.sleepEndMinute);

    emit(
      state.copyWith(
        autoDim: event.autoDim,
        sleepStartHour: event.sleepStartHour,
        sleepStartMinute: event.sleepStartMinute,
        sleepEndHour: event.sleepEndHour,
        sleepEndMinute: event.sleepEndMinute,
      ),
    );
  }
}
