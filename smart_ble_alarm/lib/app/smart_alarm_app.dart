import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:smart_ble_alarm/core/notifications/notification_service.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/theme/app_theme.dart';
import 'package:smart_ble_alarm/data/repositories/ble_repository_impl.dart';
import 'package:smart_ble_alarm/data/repositories/simulated_ble_repository_impl.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'package:smart_ble_alarm/features/account/presentation/cubit/account_cubit.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_event.dart';
import 'package:smart_ble_alarm/features/history/presentation/cubit/dismissal_history_cubit.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:smart_ble_alarm/features/timers/presentation/cubit/countdown_timer_cubit.dart';
import 'package:smart_ble_alarm/features/dedicated_clock/presentation/screens/dedicated_clock_screen.dart';
import 'package:smart_ble_alarm/app/navigation/main_screen.dart';
import 'package:smart_ble_alarm/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/screens/setup_screen.dart';

class SmartAlarmApp extends StatefulWidget {
  final SharedPreferences prefs;
  final String? rememberedDeviceId;
  final BleRepository bleRepository;
  final NotificationService notificationService;
  final bool autoInitNotifications;

  const SmartAlarmApp({
    super.key,
    required this.prefs,
    this.rememberedDeviceId,
    required this.bleRepository,
    required this.notificationService,
    this.autoInitNotifications = false,
  });

  @override
  State<SmartAlarmApp> createState() => _SmartAlarmAppState();
}

class _SmartAlarmAppState extends State<SmartAlarmApp> {
  // Active BLE backend. The temporary "Enter developer mode" button swaps this
  // for the simulator so the connected UI can be explored without a physical
  // clock. Session-only: not persisted, so a normal relaunch returns to the
  // real radio.
  late BleRepository _bleRepository = widget.bleRepository;
  late String? _rememberedDeviceId = widget.rememberedDeviceId;
  late bool _setupSkipped = widget.prefs.getBool('setupSkipped') ?? false;
  late bool _dedicatedClockEnabled =
      widget.prefs.getBool('dedicatedClockEnabled') ?? false;
  int _backendGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.autoInitNotifications) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_initNotificationsAfterLaunch(widget.notificationService));
      });
    }
  }

  void _enterDeveloperMode() {
    final previous = _bleRepository;
    setState(() {
      _bleRepository = SimulatedBleRepositoryImpl();
      _rememberedDeviceId = 'simulated_device';
      _backendGeneration++;
    });
    previous.dispose();
  }

  void _exitDeveloperMode() {
    final previous = _bleRepository;
    widget.prefs.remove('rememberedDeviceId');
    setState(() {
      _bleRepository = BleRepositoryImpl();
      _rememberedDeviceId = null;
      _backendGeneration++;
    });
    previous.dispose();
  }

  void _unpairDevice() {
    widget.prefs.remove('rememberedDeviceId');
    widget.prefs.setBool('hasSeenOnboarding', false);
    setState(() {
      _rememberedDeviceId = null;
    });
  }

  Future<void> _finishOnboarding() async {
    await widget.prefs.setBool('hasSeenOnboarding', true);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _replayOnboarding() async {
    await widget.prefs.setBool('hasSeenOnboarding', false);
    await widget.prefs.remove('setupSkipped');
    if (!mounted) return;
    setState(() {
      _setupSkipped = false;
      _rememberedDeviceId = null;
    });
  }

  void _skipPairing() {
    widget.prefs.setBool('setupSkipped', true);
    setState(() {
      _setupSkipped = true;
    });
  }

  void _completePairing(String deviceId) {
    widget.prefs.setString('rememberedDeviceId', deviceId);
    widget.prefs.remove('setupSkipped');
    setState(() {
      _rememberedDeviceId = deviceId;
      _setupSkipped = false;
    });
  }

  void _connectClock() {
    widget.prefs.remove('setupSkipped');
    setState(() {
      _setupSkipped = false;
    });
  }

  void _enableDedicatedClock() {
    widget.prefs.setBool('dedicatedClockEnabled', true);
    setState(() {
      _dedicatedClockEnabled = true;
    });
  }

  void _disableDedicatedClock() {
    widget.prefs.setBool('dedicatedClockEnabled', false);
    setState(() {
      _dedicatedClockEnabled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: ValueKey(_backendGeneration),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<BleRepository>.value(value: _bleRepository),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (context) =>
                  SettingsBloc(prefs: widget.prefs)..add(LoadSettingsEvent()),
            ),
            BlocProvider(
              create: (_) {
                final cubit = AccountCubit();
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!cubit.isClosed) {
                    unawaited(cubit.start());
                  }
                });
                return cubit;
              },
            ),
            BlocProvider(
              create: (context) {
                final bloc = BleConnectionBloc(
                  bleRepository: context.read<BleRepository>(),
                );
                final deviceId = _rememberedDeviceId;
                if (deviceId != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!bloc.isClosed) {
                      bloc.add(AutoConnectEvent(deviceId));
                    }
                  });
                }
                return bloc;
              },
            ),
            BlocProvider<AlarmBloc>(
              create: (context) => AlarmBloc(
                bleRepository: context.read<BleRepository>(),
                prefs: widget.prefs,
                notificationService: widget.notificationService,
              )..add(LoadAlarmsEvent()),
            ),
            BlocProvider<CountdownTimerCubit>(
              create: (_) => CountdownTimerCubit(prefs: widget.prefs),
            ),
            BlocProvider<DismissalHistoryCubit>(
              create: (_) => DismissalHistoryCubit(prefs: widget.prefs),
            ),
          ],
          child: BlocListener<AccountCubit, AccountState>(
            listenWhen: (previous, current) => previous.uid != current.uid,
            listener: (context, account) {
              if (account.isSignedIn) {
                context.read<AlarmBloc>().add(const SyncAlarmBackupsEvent());
              }
            },
            child: BlocBuilder<SettingsBloc, SettingsState>(
              buildWhen: (prev, curr) =>
                  prev.themeString != curr.themeString ||
                  prev.accentColorString != curr.accentColorString,
              builder: (context, settingsState) {
                return MaterialApp(
                  title: 'WakeGuard',
                  scrollBehavior: const _BounceScrollBehavior(),
                  theme: AppTheme.getTheme(
                    accentColor: AppColors.accentFromString(
                      settingsState.accentColorString,
                    ),
                    isDarkMode: false,
                  ),
                  darkTheme: AppTheme.getTheme(
                    accentColor: AppColors.accentFromString(
                      settingsState.accentColorString,
                    ),
                    isDarkMode: true,
                  ),
                  themeMode: _themeModeFor(settingsState.themeString),
                  builder: (context, child) {
                    final isLight =
                        Theme.of(context).brightness == Brightness.light;
                    return AnnotatedRegion<SystemUiOverlayStyle>(
                      value: SystemUiOverlayStyle(
                        statusBarColor: Colors.transparent,
                        statusBarBrightness: isLight
                            ? Brightness.light
                            : Brightness.dark,
                        statusBarIconBrightness: isLight
                            ? Brightness.dark
                            : Brightness.light,
                      ),
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                  home: _buildHome(),
                  debugShowCheckedModeBanner: false,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  ThemeMode _themeModeFor(String theme) {
    switch (theme) {
      case 'Light':
        return ThemeMode.light;
      case 'System':
        return ThemeMode.system;
      case 'Dark':
      default:
        return ThemeMode.dark;
    }
  }

  Widget _buildHome() {
    if (_dedicatedClockEnabled) {
      return DedicatedClockScreen(onExit: _disableDedicatedClock);
    }

    if (_rememberedDeviceId != null) {
      final usingSimulator = _bleRepository is SimulatedBleRepositoryImpl;
      return MainScreen(
        onExitDeveloperMode: usingSimulator ? _exitDeveloperMode : null,
        onUnpairDevice: usingSimulator ? null : _unpairDevice,
        onSetupDedicatedClock: _enableDedicatedClock,
        onReplayOnboarding: _replayOnboarding,
      );
    }

    if (_setupSkipped) {
      return MainScreen(
        onConnectClock: _connectClock,
        onSetupDedicatedClock: _enableDedicatedClock,
        onReplayOnboarding: _replayOnboarding,
      );
    }

    final hasSeenOnboarding =
        widget.prefs.getBool('hasSeenOnboarding') ?? false;
    if (hasSeenOnboarding) {
      return SetupScreen(
        prefs: widget.prefs,
        onEnterDeveloperMode: kDebugMode ? _enterDeveloperMode : null,
        onSkip: _skipPairing,
        onConnected: _completePairing,
        onReplayOnboarding: _replayOnboarding,
        onSetupDedicatedClock: _enableDedicatedClock,
      );
    }

    return OnboardingScreen(
      prefs: widget.prefs,
      onComplete: _finishOnboarding,
      onSetupDedicatedClock: _enableDedicatedClock,
    );
  }
}

Future<void> _initNotificationsAfterLaunch(
  NotificationService notificationService,
) async {
  try {
    await notificationService.init();
  } catch (error, stackTrace) {
    debugPrint('NotificationService.init failed: $error\n$stackTrace');
  }
}

class _BounceScrollBehavior extends MaterialScrollBehavior {
  const _BounceScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(
        decelerationRate: ScrollDecelerationRate.fast,
      );

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
