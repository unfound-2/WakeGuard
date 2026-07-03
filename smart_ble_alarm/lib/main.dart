import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/app_colors.dart';
import 'data/repositories/ble_repository_impl.dart';
import 'data/repositories/simulated_ble_repository_impl.dart';
import 'domain/repositories/ble_repository.dart';
import 'presentation/blocs/ble_bloc/ble_bloc.dart';
import 'presentation/blocs/ble_bloc/ble_event.dart';
import 'presentation/blocs/alarm_bloc/alarm_bloc.dart';
import 'presentation/blocs/settings_bloc/settings_bloc.dart';
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

  runApp(
    SmartAlarmApp(
      prefs: prefs,
      rememberedDeviceId: rememberedDeviceId,
      bleRepository: bleRepository,
    ),
  );
}

class SmartAlarmApp extends StatelessWidget {
  final SharedPreferences prefs;
  final String? rememberedDeviceId;
  final BleRepository bleRepository;

  const SmartAlarmApp({
    super.key,
    required this.prefs,
    this.rememberedDeviceId,
    required this.bleRepository,
  });

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<BleRepository>.value(value: bleRepository),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) =>
                SettingsBloc(prefs: prefs)..add(LoadSettingsEvent()),
          ),
          BlocProvider(
            create: (context) {
              final bloc = BleConnectionBloc(
                bleRepository: context.read<BleRepository>(),
              );
              if (rememberedDeviceId != null) {
                bloc.add(AutoConnectEvent(rememberedDeviceId!));
              }
              return bloc;
            },
          ),
          BlocProvider<AlarmBloc>(
            create: (_) =>
                AlarmBloc(bleRepository: bleRepository, prefs: prefs)
                  ..add(LoadAlarmsEvent()),
          ),
        ],
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            Color accentColor = AppColors.primaryOrange;
            if (settingsState.accentColorString == 'Cyber Cyan') {
              accentColor = const Color(0xFF00F0FF); // Cyber Cyan
            } else if (settingsState.accentColorString == 'Matrix Green') {
              accentColor = const Color(0xFF00FF41); // Matrix Green
            } else if (settingsState.accentColorString == 'Neon Blue') {
              accentColor = AppColors.neonBlue;
            }

            bool isDark = settingsState.themeString != 'Light';

            return MaterialApp(
              title: 'WakeGuard',
              theme: AppTheme.getTheme(
                accentColor: accentColor,
                isDarkMode: isDark,
              ),
              home: prefs.getString('rememberedDeviceId') == null
                  ? (prefs.getBool('hasSeenOnboarding') ?? false
                        ? SetupScreen(prefs: prefs)
                        : OnboardingScreen(prefs: prefs))
                  : const MainScreen(),
              debugShowCheckedModeBanner: false,
            );
          },
        ),
      ),
    );
  }
}
