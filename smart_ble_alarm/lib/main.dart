import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'core/notifications/notification_service.dart';
import 'data/repositories/ble_repository_impl.dart';
import 'data/repositories/simulated_ble_repository_impl.dart';
import 'domain/repositories/ble_repository.dart';
import 'presentation/blocs/ble_bloc/ble_bloc.dart';
import 'presentation/blocs/ble_bloc/ble_event.dart';
import 'presentation/blocs/alarm_bloc/alarm_bloc.dart';
import 'presentation/blocs/settings_bloc/settings_bloc.dart';
import 'presentation/blocs/timer_cubit/countdown_timer_cubit.dart';
import 'presentation/blocs/history_cubit/dismissal_history_cubit.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/setup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final String? rememberedDeviceId = prefs.getString('rememberedDeviceId');

  BleRepository bleRepository;
  if (rememberedDeviceId == 'simulated_device') {
    bleRepository = SimulatedBleRepositoryImpl();
  } else {
    bleRepository = BleRepositoryImpl();
  }

  // Phone-side backup alarm scheduler. Initialised before the app so the first
  // LoadAlarmsEvent can schedule notifications immediately; a failure here must
  // not stop the app from launching, hence the try/catch.
  final notificationService = NotificationService();
  try {
    await notificationService.init();
  } catch (_) {}

  runApp(
    SmartAlarmApp(
      prefs: prefs,
      rememberedDeviceId: rememberedDeviceId,
      bleRepository: bleRepository,
      notificationService: notificationService,
    ),
  );
}

class SmartAlarmApp extends StatefulWidget {
  final SharedPreferences prefs;
  final String? rememberedDeviceId;
  final BleRepository bleRepository;
  final NotificationService notificationService;

  const SmartAlarmApp({
    super.key,
    required this.prefs,
    this.rememberedDeviceId,
    required this.bleRepository,
    required this.notificationService,
  });

  @override
  State<SmartAlarmApp> createState() => _SmartAlarmAppState();
}

class _SmartAlarmAppState extends State<SmartAlarmApp> {
  // Active BLE backend. The temporary "Enter developer mode" button swaps this
  // for the simulator so the connected UI can be explored without a physical
  // clock. Session-only — not persisted, so a normal relaunch returns to the
  // real radio.
  late BleRepository _bleRepository = widget.bleRepository;
  late String? _rememberedDeviceId = widget.rememberedDeviceId;
  // Bumped to tear down and recreate the provider/bloc subtree so the new
  // BleConnectionBloc binds to the freshly-selected repository.
  int _backendGeneration = 0;

  void _enterDeveloperMode() {
    // Release the outgoing backend's subscriptions/stream controllers before
    // abandoning it — RepositoryProvider.value never disposes it for us.
    final previous = _bleRepository;
    setState(() {
      _bleRepository = SimulatedBleRepositoryImpl();
      _rememberedDeviceId = 'simulated_device';
      _backendGeneration++;
    });
    previous.dispose();
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
              create: (context) {
                final bloc = BleConnectionBloc(
                  bleRepository: context.read<BleRepository>(),
                );
                if (_rememberedDeviceId != null) {
                  bloc.add(AutoConnectEvent(_rememberedDeviceId!));
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
          child: BlocBuilder<SettingsBloc, SettingsState>(
            // Only the theme/accent drive MaterialApp; rebuilding the whole app
            // tree when unrelated settings (24h, auto-dim, sleep times) change
            // is wasteful, so gate the rebuild to the fields actually used here.
            buildWhen: (prev, curr) =>
                prev.themeString != curr.themeString ||
                prev.accentColorString != curr.accentColorString,
            builder: (context, settingsState) {
              final accentColor = AppColors.accentFromString(
                settingsState.accentColorString,
              );

              final ThemeMode themeMode;
              switch (settingsState.themeString) {
                case 'Light':
                  themeMode = ThemeMode.light;
                  break;
                case 'System':
                  themeMode = ThemeMode.system;
                  break;
                case 'Dark':
                default:
                  themeMode = ThemeMode.dark;
              }

              return MaterialApp(
                title: 'WakeGuard',
                scrollBehavior: const _BounceScrollBehavior(),
                theme: AppTheme.getTheme(
                  accentColor: accentColor,
                  isDarkMode: false,
                ),
                darkTheme: AppTheme.getTheme(
                  accentColor: accentColor,
                  isDarkMode: true,
                ),
                themeMode: themeMode,
                home: _rememberedDeviceId == null
                    ? ((widget.prefs.getBool('hasSeenOnboarding') ?? false)
                          ? SetupScreen(
                              prefs: widget.prefs,
                              onEnterDeveloperMode: _enterDeveloperMode,
                            )
                          : OnboardingScreen(prefs: widget.prefs))
                    : const MainScreen(),
                debugShowCheckedModeBanner: false,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// App-wide scroll feel: iOS-style rubber-band bounce on every platform, with
/// no overscroll indicator. This removes Android's default "stretch" (which
/// visibly distorts text and cards at the edges) and the glow indicator — the
/// content simply springs back when dragged past the end.
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
    // Bounce alone communicates the edge — suppress the stretch/glow overlay.
    return child;
  }
}
