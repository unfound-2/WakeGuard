import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/ble/ble_payloads.dart';
import '../../core/ble/clock_sync.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/ble_bloc/ble_event.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../../domain/repositories/ble_repository.dart';
import '../widgets/liquid_glass_tab_bar.dart';
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

  /// Top-of-screen connectivity banner. Surfaces three distinct states the app
  /// previously collapsed into a bare "Disconnected":
  ///  - the Bluetooth radio itself is off / unauthorised (the app can't scan at
  ///    all — [adapterState] was exposed by the repository but never consumed);
  ///  - a reconnect is actively in progress;
  ///  - disconnected, now with a one-tap Retry instead of a dead end.
  Widget _buildConnectivityBanner() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        return StreamBuilder<BluetoothAdapterState>(
          stream: context.read<BleRepository>().adapterState,
          builder: (context, snapshot) {
            final theme = Theme.of(context);
            final adapter = snapshot.data;
            final radioUnavailable =
                adapter == BluetoothAdapterState.off ||
                adapter == BluetoothAdapterState.unauthorized ||
                adapter == BluetoothAdapterState.unavailable;

            if (radioUnavailable) {
              final unauthorized =
                  adapter == BluetoothAdapterState.unauthorized;
              return _statusBanner(
                context,
                color: theme.colorScheme.error,
                icon: Icons.bluetooth_disabled_rounded,
                message: unauthorized
                    ? 'Bluetooth access is off — enable it in Settings to reach your clock.'
                    : 'Bluetooth is off — turn it on to reach your clock.',
              );
            }

            if (bleState is BleConnecting || bleState is BleScanning) {
              return _statusBanner(
                context,
                color: theme.colorScheme.primary,
                icon: Icons.bluetooth_searching_rounded,
                message: 'Reconnecting to your clock…',
              );
            }

            if (bleState is BleDisconnected) {
              return _statusBanner(
                context,
                color: theme.colorScheme.error,
                icon: Icons.cloud_off_rounded,
                message:
                    'Disconnected — changes save locally and sync when the clock reconnects.',
                action: TextButton(
                  onPressed: () => context.read<BleConnectionBloc>().add(
                    ReconnectEvent(),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Retry',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              );
            }

            return const SizedBox.shrink();
          },
        );
      },
    );
  }

  Widget _statusBanner(
    BuildContext context, {
    required Color color,
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 10,
        bottom: 10,
        left: 16,
        right: 16,
      ),
      color: color.withValues(alpha: 0.14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (action != null) ...[const SizedBox(width: 4), action],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<BleConnectionBloc, BleState>(
          listener: (context, state) {
            if (state is BleConnected) {
              _listenForDeviceFrames(context, state);
              syncConnectedClock(context, state.device);
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
        // Re-run backup-notification scheduling when the toggle flips; the
        // service itself reads the pref and cancels or schedules accordingly.
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) =>
              previous.backupNotificationsEnabled !=
              current.backupNotificationsEnabled,
          listener: (context, state) {
            context.read<AlarmBloc>().add(LoadAlarmsEvent());
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
            _buildConnectivityBanner(),
            // IndexedStack keeps every tab mounted so scroll position and
            // in-tab state (e.g. live timer tickers) survive tab switches.
            Expanded(
              child: IndexedStack(index: _currentIndex, children: _tabs),
            ),
          ],
        ),
        // Floating Liquid Glass tab bar; content scrolls underneath thanks to
        // extendBody, so each tab pads its scrollable bottom edge.
        bottomNavigationBar: LiquidGlassTabBar(
          currentIndex: _currentIndex,
          onSelected: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            LiquidGlassTabItem(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: 'Home',
            ),
            LiquidGlassTabItem(
              icon: Icons.access_alarm_outlined,
              selectedIcon: Icons.access_alarm_rounded,
              label: 'Alarms',
            ),
            LiquidGlassTabItem(
              icon: Icons.schedule_outlined,
              selectedIcon: Icons.schedule_rounded,
              label: 'Clock',
            ),
            LiquidGlassTabItem(
              icon: Icons.settings_outlined,
              selectedIcon: Icons.settings_rounded,
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
