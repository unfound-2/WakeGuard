import 'dart:async';
import 'dart:ui' as dart_ui;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/ble/ble_payloads.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/ble_bloc/ble_event.dart';
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

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription<List<int>>? _frameSubscription;

  final List<Widget> _tabs = [
    const HomeTab(),
    const AlarmsTab(),
    const ClockTab(),
    const SettingsScreen(isTab: true),
  ];

  @override
  void initState() {
    super.initState();
    // Drive the connection off the app lifecycle: hold the link only while the
    // app is in the foreground, and release the radio in the background. The
    // clock rings alarms autonomously, so there's no reason to stay connected
    // (or keep BLE alive in the background) when the app is closed.
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final bleBloc = context.read<BleConnectionBloc>();
    if (state == AppLifecycleState.resumed) {
      bleBloc.add(ReconnectEvent());
    } else if (state == AppLifecycleState.paused) {
      bleBloc.add(ReleaseConnectionEvent());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameSubscription?.cancel();
    super.dispose();
  }

  Future<void> _syncConnectedClock(
    BuildContext context,
    BleConnected state,
  ) async {
    final bleRepo = context.read<BleRepository>();
    final alarmBloc = context.read<AlarmBloc>();
    final device = state.device;
    final settings = context.read<SettingsBloc>().state;

    try {
      await bleRepo.sendCommand(device, 0x04, const []);
      await bleRepo.sendCommand(
        device,
        0x01,
        BlePayloads.currentEpochSeconds(),
      );
      final alarmSync = Completer<void>();
      alarmBloc.add(SyncAlarmsToDeviceEvent(device, completer: alarmSync));
      await alarmSync.future;
      await bleRepo.sendCommand(
        device,
        0x06,
        BlePayloads.clockSettings(
          autoDim: settings.autoDim,
          sleepStartHour: settings.sleepStartHour,
          sleepStartMinute: settings.sleepStartMinute,
          sleepEndHour: settings.sleepEndHour,
          sleepEndMinute: settings.sleepEndMinute,
        ),
      );
      await bleRepo.sendCommand(device, 0x05, const []);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Clock sync failed. Local changes are still saved.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _listenForDeviceFrames(BuildContext context, BleConnected state) {
    final bleRepo = context.read<BleRepository>();
    final alarmBloc = context.read<AlarmBloc>();
    final device = state.device;

    _frameSubscription?.cancel();
    _frameSubscription = bleRepo.receiveFrames(device).listen((frame) async {
      if (!mounted || frame.length < 2) return;

      final command = frame[0];
      final len = frame[1];
      final data = frame.skip(2).take(len).toList();

      if (command == 0x08 && data.isNotEmpty) {
        final alarmId = data.first;
        alarmBloc.add(SetRingingAlarmEvent(alarmId));
        try {
          await bleRepo.sendCommand(device, 0x88, [alarmId]);
        } catch (_) {}
      } else if (command == 0x89) {
        alarmBloc.add(const SetRingingAlarmEvent(null));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<BleConnectionBloc, BleState>(
          listener: (context, state) {
            if (state is BleConnected) {
              _listenForDeviceFrames(context, state);
              _syncConnectedClock(context, state);
            } else if (state is BleDisconnected) {
              _frameSubscription?.cancel();
              _frameSubscription = null;
            }
          },
        ),
        BlocListener<AlarmBloc, AlarmState>(
          listenWhen: (previous, current) =>
              previous.syncError != current.syncError &&
              current.syncError != null,
          listener: (context, state) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.syncError!),
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
            );
          },
        ),
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) =>
              previous.autoDim != current.autoDim ||
              previous.sleepStartHour != current.sleepStartHour ||
              previous.sleepStartMinute != current.sleepStartMinute ||
              previous.sleepEndHour != current.sleepEndHour ||
              previous.sleepEndMinute != current.sleepEndMinute,
          listener: (context, state) async {
            final bleState = context.read<BleConnectionBloc>().state;
            if (bleState is BleConnected) {
              final bleRepo = context.read<BleRepository>();
              try {
                await bleRepo.sendCommand(
                  bleState.device,
                  0x06,
                  BlePayloads.clockSettings(
                    autoDim: state.autoDim,
                    sleepStartHour: state.sleepStartHour,
                    sleepStartMinute: state.sleepStartMinute,
                    sleepEndHour: state.sleepEndHour,
                    sleepEndMinute: state.sleepEndMinute,
                  ),
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Clock settings saved locally, but sync failed.',
                    ),
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                );
              }
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
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 10,
                      bottom: 10,
                      left: 16,
                      right: 16,
                    ),
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          size: 16,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Disconnected — changes save locally and sync when the clock reconnects.',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            // IndexedStack keeps every tab mounted so scroll position and
            // in-tab state (e.g. live timer tickers) survive tab switches.
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _tabs),
            ),
          ],
        ),
        bottomNavigationBar: ClipRRect(
          child: BackdropFilter(
            filter: dart_ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.5),
              ),
              child: NavigationBarTheme(
                data: NavigationBarThemeData(
                  backgroundColor: Colors.transparent,
                  indicatorColor: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.2),
                  labelTextStyle: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      );
                    }
                    return TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    );
                  }),
                  iconTheme: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return IconThemeData(
                        color: Theme.of(context).colorScheme.primary,
                      );
                    }
                    return IconThemeData(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    );
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
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_outlined),
                      selectedIcon: Icon(Icons.dashboard),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.access_alarm_outlined),
                      selectedIcon: Icon(Icons.access_alarm),
                      label: 'Alarms',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.watch_outlined),
                      selectedIcon: Icon(Icons.watch),
                      label: 'Clock',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: 'Settings',
                    ),
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
