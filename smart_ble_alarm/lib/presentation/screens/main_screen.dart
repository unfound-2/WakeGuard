import 'dart:ui' as dart_ui;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../../domain/repositories/ble_repository.dart';
import 'tabs/home_tab.dart';
import 'tabs/alarms_tab.dart';
import 'tabs/clock_tab.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const HomeTab(),
    const AlarmsTab(),
    const ClockTab(),
    const SettingsScreen(isTab: true),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<BleConnectionBloc, BleState>(
          listener: (context, state) {
            if (state is BleConnected) {
              final bleRepo = context.read<BleRepository>();
              final device = state.device;
              
              // 1. Time Sync (4-byte Unix Epoch)
              final now = DateTime.now();
              final epoch = now.millisecondsSinceEpoch ~/ 1000;
              final timeBytes = [
                (epoch >> 24) & 0xFF,
                (epoch >> 16) & 0xFF,
                (epoch >> 8) & 0xFF,
                epoch & 0xFF,
              ];
              try { bleRepo.sendCommand(device, 0x01, timeBytes); } catch (_) {}
              
              // 2. Alarm Sync
              final alarmBloc = context.read<AlarmBloc>();
              for (var alarm in alarmBloc.state.alarms) {
                alarmBloc.add(AddOrUpdateAlarmEvent(alarm, device));
              }
              
              // 3. Config Sync
              final settings = context.read<SettingsBloc>().state;
              try { 
                bleRepo.sendCommand(device, 0x06, [
                  settings.autoDim ? 1 : 0,
                  settings.sleepStartHour,
                  settings.sleepStartMinute,
                  settings.sleepEndHour,
                  settings.sleepEndMinute,
                ]); 
              } catch (_) {}
            }
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) => 
              previous.autoDim != current.autoDim ||
              previous.sleepStartHour != current.sleepStartHour ||
              previous.sleepStartMinute != current.sleepStartMinute ||
              previous.sleepEndHour != current.sleepEndHour ||
              previous.sleepEndMinute != current.sleepEndMinute,
          listener: (context, state) {
            final bleState = context.read<BleConnectionBloc>().state;
            if (bleState is BleConnected) {
              final bleRepo = context.read<BleRepository>();
              try { 
                bleRepo.sendCommand(bleState.device, 0x06, [
                  state.autoDim ? 1 : 0,
                  state.sleepStartHour,
                  state.sleepStartMinute,
                  state.sleepEndHour,
                  state.sleepEndMinute,
                ]); 
              } catch (_) {}
            }
          },
        ),
      ],
      child: Scaffold(
        extendBody: true,
        body: Column(
        children: [
          BlocBuilder<BleConnectionBloc, BleState>(
            builder: (context, state) {
              if (state is BleDisconnected) {
                return Container(
                  width: double.infinity,
                  color: AppColors.error,
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    bottom: 8,
                    left: 16,
                    right: 16,
                  ),
                  child: const Text(
                    'Device disconnected. Changes will be saved locally and automatically synchronized when the clock reconnects.',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(
            child: _tabs[_currentIndex],
          ),
        ],
      ),
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: dart_ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
            ),
            child: NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: Colors.transparent,
            indicatorColor: AppColors.primaryOrange.withValues(alpha: 0.2),
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold, fontSize: 12);
              }
              return const TextStyle(color: AppColors.textSecondary, fontSize: 12);
            }),
            iconTheme: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: AppColors.primaryOrange);
              }
              return const IconThemeData(color: AppColors.textSecondary);
            }),
          ),
          child: NavigationBar(
            elevation: 0,
            backgroundColor: Colors.transparent,
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: const [
              NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.access_alarm_outlined), selectedIcon: Icon(Icons.access_alarm), label: 'Alarms'),
              NavigationDestination(icon: Icon(Icons.watch_outlined), selectedIcon: Icon(Icons.watch), label: 'Clock'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        ),
      ),
    ),
  ),
),
    );
  }
}
