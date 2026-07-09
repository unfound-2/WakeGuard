import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/ble/ble_payloads.dart';
import '../../core/ble/clock_sync.dart';
import '../../core/ui/app_snackbar.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/ble_bloc/ble_event.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../../domain/repositories/ble_repository.dart';
import '../../domain/entities/alarm.dart';
import '../../core/utils/alarm_time_utils.dart';
import '../widgets/liquid_glass_tab_bar.dart';
import '../widgets/ringing_dismissal.dart';
import 'tabs/home_tab.dart';
import 'tabs/alarms_tab.dart';
import 'tabs/display_tab.dart';
import 'settings_screen.dart';

class MainScreen extends StatefulWidget {
  /// When non-null, the app is running on the simulated clock and Settings shows
  /// a button to leave developer mode and return to pairing a real clock.
  final VoidCallback? onExitDeveloperMode;

  /// When non-null (a real clock is paired), Settings shows an "Unpair Device"
  /// action that forgets the clock and restarts onboarding. Wired up in
  /// `main.dart` so the app-level remembered-device state and the persisted
  /// prefs stay in agreement.
  final VoidCallback? onUnpairDevice;

  /// When non-null (the user skipped pairing and has no clock), Settings shows a
  /// "Connect a Clock" action that returns to the pairing screen. Wired in
  /// `main.dart`.
  final VoidCallback? onConnectClock;

  const MainScreen({
    super.key,
    this.onExitDeveloperMode,
    this.onUnpairDevice,
    this.onConnectClock,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  StreamSubscription<List<int>>? _frameSubscription;
  Timer? _weatherTimer;

  void _openTab(int index) => setState(() => _currentIndex = index);

  // Built per-frame so HomeTab can receive a live callback into the Alarms tab
  // (e.g. tapping the next-alarm or live-timer card). IndexedStack keeps each
  // tab's element/state alive regardless of these widgets being rebuilt.
  List<Widget> _buildTabs() => [
    HomeTab(onOpenAlarms: () => _openTab(1)),
    const AlarmsTab(),
    const DisplayTab(),
    SettingsScreen(
      isTab: true,
      onExitDeveloperMode: widget.onExitDeveloperMode,
      onUnpairDevice: widget.onUnpairDevice,
      onConnectClock: widget.onConnectClock,
    ),
  ];

  @override
  void initState() {
    super.initState();
    // Drive the connection off the app lifecycle: hold the link only while the
    // app is in the foreground, and release the radio in the background. The
    // clock rings alarms autonomously, so there's no reason to stay connected
    // (or keep BLE alive in the background) when the app is closed.
    WidgetsBinding.instance.addObserver(this);

    // Refresh the clock's weather periodically while connected. The initial push
    // rides the on-connect sync; this keeps it current over a long session. It's
    // best-effort and unawaited, so a failed fetch is silently skipped.
    _weatherTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (!mounted) return;
      final bleState = context.read<BleConnectionBloc>().state;
      if (bleState is! BleConnected) return;
      unawaited(
        pushWeatherToClock(
          context.read<BleRepository>(),
          bleState.device,
          context.read<SettingsBloc>().state,
        ),
      );
    });
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
    _weatherTimer?.cancel();
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
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    // Keep a ≥44px hit area for accessibility rather than the
                    // previous shrink-wrapped (sub-44px) target.
                    minimumSize: const Size(48, 44),
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
      // No status-bar inset here: the parent SafeArea already positions the
      // overlay below the status bar.
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      decoration: BoxDecoration(
        // Opaque (blended over the surface) so the banner reads cleanly while
        // floating OVER content, rather than letting content bleed through.
        color: Color.alphaBlend(
          color.withValues(alpha: 0.16),
          Theme.of(context).colorScheme.surface,
        ),
        border: Border(
          bottom: BorderSide(color: color.withValues(alpha: 0.35), width: 1),
        ),
      ),
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

  /// A ringing-alarm banner that slides down over every tab whenever an alarm is
  /// sounding. Tapping the banner (or its button) runs the task-aware dismissal:
  /// "Dismiss" for a no-task alarm, "Take Photo" for an item alarm, "Scan QR"
  /// for a QR alarm — the same [RingingDismissal] the Home card and Alarms row
  /// use, so all three surfaces always agree.
  Widget _buildRingingBanner() {
    return BlocBuilder<AlarmBloc, AlarmState>(
      buildWhen: (prev, curr) =>
          prev.ringingAlarmId != curr.ringingAlarmId ||
          prev.alarms != curr.alarms,
      builder: (context, alarmState) {
        final id = alarmState.ringingAlarmId;
        Alarm? ringing;
        if (id != null) {
          for (final a in alarmState.alarms) {
            if (a.id == id) {
              ringing = a;
              break;
            }
          }
        }
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: ringing == null
              ? const SizedBox(width: double.infinity)
              : _ringingBannerContent(context, ringing),
        );
      },
    );
  }

  Widget _ringingBannerContent(BuildContext context, Alarm alarm) {
    final scheme = Theme.of(context).colorScheme;
    final error = scheme.error;
    final is24Hour = context.read<SettingsBloc>().state.is24HourTime;
    final timeStr = AlarmTimeUtils.formatTime(
      alarm.hour,
      alarm.minute,
      is24Hour: is24Hour,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => RingingDismissal.trigger(context, alarm),
        child: Container(
          width: double.infinity,
          // No status-bar inset here: the parent SafeArea handles it.
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            // Opaque so the ringing alert fully covers content it floats over.
            color: Color.alphaBlend(
              error.withValues(alpha: 0.16),
              scheme.surface,
            ),
            border: Border(
              bottom: BorderSide(
                color: error.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: error.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          'ALARM RINGING',
                          style: TextStyle(
                            color: error,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${alarm.displayName} · ${RingingDismissal.instruction(alarm)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Flexible + a single-line, ellipsizing label so bold/large text
              // shrinks this compact button to fit the banner instead of
              // overflowing the row (normal text is unaffected).
              Flexible(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: error,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => RingingDismissal.trigger(context, alarm),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(RingingDismissal.actionIcon(alarm), size: 18),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          RingingDismissal.actionLabel(alarm),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
            // Feedback for a per-change direct push (edit/delete while
            // connected). Replaces any prior card instead of queueing behind it.
            showAppSnackBar(context, state.syncError!, type: AppSnackType.error);
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
        // Live-push clock-face display settings (theme/accent/seconds/date and
        // the 24-hour format) the moment they change, so tweaks on the Display
        // tab show on the clock immediately. Disconnected: kick a reconnect so
        // the change flushes through the on-connect full sync.
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) =>
              previous.is24HourTime != current.is24HourTime ||
              previous.clockThemeLight != current.clockThemeLight ||
              previous.clockAccentIndex != current.clockAccentIndex ||
              previous.clockShowSeconds != current.clockShowSeconds ||
              previous.clockShowDate != current.clockShowDate ||
              previous.clockShowDayOfWeek != current.clockShowDayOfWeek ||
              previous.clockDateFormat != current.clockDateFormat,
          listener: (context, state) async {
            final bleState = context.read<BleConnectionBloc>().state;
            if (bleState is! BleConnected) {
              context.read<BleConnectionBloc>().add(ReconnectEvent());
              return;
            }
            try {
              await context.read<BleRepository>().sendCommand(
                bleState.device,
                0x06,
                BlePayloads.clockDisplaySettings(
                  use24h: state.is24HourTime,
                  showSeconds: state.clockShowSeconds,
                  showDate: state.clockShowDate,
                  showDayOfWeek: state.clockShowDayOfWeek,
                  dateFormat: state.clockDateFormat,
                  theme: state.clockThemeLight ? 1 : 0,
                  accent: state.clockAccentIndex,
                ),
              );
            } catch (_) {
              if (!context.mounted) return;
              showAppSnackBar(
                context,
                'Display settings saved, but the clock update failed.',
                type: AppSnackType.error,
              );
            }
          },
        ),
        // Live-push the display-sleep schedule (0x0D) the moment it changes, so the
        // clock adopts the new blank window immediately. Disconnected: kick a
        // reconnect so the change flushes through the on-connect full sync.
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) =>
              previous.clockSleepEnabled != current.clockSleepEnabled ||
              previous.clockSleepStartMinutes !=
                  current.clockSleepStartMinutes ||
              previous.clockSleepEndMinutes != current.clockSleepEndMinutes,
          listener: (context, state) async {
            final bleState = context.read<BleConnectionBloc>().state;
            if (bleState is! BleConnected) {
              context.read<BleConnectionBloc>().add(ReconnectEvent());
              return;
            }
            try {
              await context.read<BleRepository>().sendCommand(
                bleState.device,
                0x0D,
                BlePayloads.clockSleepSchedule(
                  enabled: state.clockSleepEnabled,
                  startHour: state.clockSleepStartMinutes ~/ 60,
                  startMinute: state.clockSleepStartMinutes % 60,
                  endHour: state.clockSleepEndMinutes ~/ 60,
                  endMinute: state.clockSleepEndMinutes % 60,
                ),
              );
            } catch (_) {
              if (!context.mounted) return;
              showAppSnackBar(
                context,
                'Sleep schedule saved, but the clock update failed.',
                type: AppSnackType.error,
              );
            }
          },
        ),
        // Live-push weather the moment the user toggles it on/off or flips the
        // unit, so the clock's corner updates without waiting for the next sync.
        // Disconnected changes flush through the on-connect sync.
        BlocListener<SettingsBloc, SettingsState>(
          listenWhen: (previous, current) =>
              previous.showWeather != current.showWeather ||
              previous.weatherFahrenheit != current.weatherFahrenheit,
          listener: (context, state) {
            final bleState = context.read<BleConnectionBloc>().state;
            if (bleState is! BleConnected) return;
            unawaited(
              pushWeatherToClock(
                context.read<BleRepository>(),
                bleState.device,
                state,
              ),
            );
          },
        ),
        // Any alarm change auto-syncs to the clock: when connected, AlarmBloc
        // pushes the alarm directly; when disconnected, kick a reconnect so the
        // pending change flushes through the on-connect full sync instead of
        // waiting for the next app-open / manual reconnect.
        BlocListener<AlarmBloc, AlarmState>(
          listenWhen: (previous, current) =>
              previous.alarms != current.alarms ||
              previous.pendingDeleteIds != current.pendingDeleteIds,
          listener: (context, state) {
            if (context.read<BleConnectionBloc>().state is! BleConnected) {
              context.read<BleConnectionBloc>().add(ReconnectEvent());
            }
          },
        ),
      ],
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            // Content fills the whole screen; each tab applies its own top
            // SafeArea. IndexedStack keeps every tab mounted so scroll position
            // and in-tab state (e.g. live timer tickers) survive tab switches.
            Positioned.fill(
              child: IndexedStack(
                index: _currentIndex,
                children: _buildTabs(),
              ),
            ),
            // Banners are an OVERLAY, not part of the layout: they float over
            // the content instead of reserving height (which pushed content
            // down and double-counted the status-bar inset). SafeArea(top) pins
            // them just below the status bar so the system clock/battery stay
            // legible on the app background.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRingingBanner(),
                    _buildConnectivityBanner(),
                  ],
                ),
              ),
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
              icon: Icons.tune_outlined,
              selectedIcon: Icons.tune_rounded,
              label: 'Display',
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
