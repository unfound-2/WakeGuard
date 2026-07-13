import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_state.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_event.dart';
import 'package:smart_ble_alarm/app/navigation/main_screen.dart';

class SetupScreen extends StatefulWidget {
  final SharedPreferences prefs;

  /// Temporary hook: swaps the app onto the simulated clock so the connected
  /// UI can be explored without pairing real hardware. When null the
  /// developer-mode button is hidden.
  final VoidCallback? onEnterDeveloperMode;

  /// Invoked when the user taps "Skip". When provided (from `main.dart`), the
  /// app persists the skip and shows the main app; the callback owns navigation
  /// so the skip choice survives relaunches. Falls back to local navigation if
  /// null.
  final VoidCallback? onSkip;

  /// Invoked when a real clock connects. When provided, `main.dart` persists the
  /// device id and swaps the declarative route to MainScreen.
  final ValueChanged<String>? onConnected;

  /// Clears first-run state and shows onboarding again.
  final Future<void> Function()? onReplayOnboarding;

  /// Turns THIS device into a standby Dedicated Clock (Beta). Surfaced here for
  /// users who have no hardware clock to pair. Wired from `main.dart`; null hides
  /// the affordance.
  final VoidCallback? onSetupDedicatedClock;

  const SetupScreen({
    super.key,
    required this.prefs,
    this.onEnterDeveloperMode,
    this.onSkip,
    this.onConnected,
    this.onReplayOnboarding,
    this.onSetupDedicatedClock,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> with WidgetsBindingObserver {
  _BluetoothPermissionIssue _permissionIssue = _BluetoothPermissionIssue.none;
  bool _permissionRequestInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startScan();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        _permissionIssue == _BluetoothPermissionIssue.none) {
      return;
    }
    // Returning from iOS/Android Settings is the moment a previously denied
    // permission may have changed. Re-check and, if access is now available,
    // immediately resume the pairing scan instead of leaving the screen stuck.
    unawaited(_startScan());
  }

  Future<void> _startScan() async {
    if (_permissionRequestInFlight) return;
    final hasAccess = await _ensureBluetoothAccess();
    if (!mounted || !hasAccess) return;
    context.read<BleConnectionBloc>().add(StartScanEvent());
  }

  Future<bool> _ensureBluetoothAccess() async {
    setState(() => _permissionRequestInFlight = true);
    var issue = _BluetoothPermissionIssue.none;
    try {
      final permissions = [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        if (defaultTargetPlatform == TargetPlatform.android)
          Permission.locationWhenInUse,
      ];
      final statuses = await permissions.request();
      final bluetoothBlocked =
          _statusBlocks(statuses[Permission.bluetoothScan]) ||
          _statusBlocks(statuses[Permission.bluetoothConnect]);
      final locationBlocked =
          defaultTargetPlatform == TargetPlatform.android &&
          _statusBlocks(statuses[Permission.locationWhenInUse]);
      if (bluetoothBlocked) {
        issue = _BluetoothPermissionIssue.bluetooth;
      } else if (locationBlocked) {
        issue = _BluetoothPermissionIssue.location;
      }
    } catch (_) {
      // Permission plugins are unavailable in widget tests and some desktop runs.
    }

    if (!mounted) return false;
    setState(() {
      _permissionIssue = issue;
      _permissionRequestInFlight = false;
    });
    return issue == _BluetoothPermissionIssue.none;
  }

  bool _statusBlocks(PermissionStatus? status) {
    if (status == null) return false;
    return status.isDenied || status.isPermanentlyDenied || status.isRestricted;
  }

  Future<void> _openSystemSettings() async {
    await openAppSettings();
  }

  /// Enter the app without pairing a clock. WakeGuard works fully offline —
  /// alarms are saved locally and mirrored to backup notifications — so this
  /// just stops the scan and opens the main app. No rememberedDeviceId is
  /// written, so the next launch returns to this screen to pair.
  Future<void> _skipPairing() async {
    context.read<BleConnectionBloc>().add(StopScanEvent());
    await widget.prefs.setBool('setupSkipped', true);
    await widget.prefs.setBool('hasSeenOnboarding', true);
    if (!mounted) return;

    final onSkip = widget.onSkip;
    if (onSkip != null) {
      // App-level handler persists the skip and swaps `home:` to MainScreen.
      onSkip();
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  void _enterDeveloperMode() {
    context.read<BleConnectionBloc>().add(StopScanEvent());
    widget.onEnterDeveloperMode?.call();
  }

  Future<void> _replayOnboarding() async {
    context.read<BleConnectionBloc>().add(StopScanEvent());
    await widget.prefs.setBool('hasSeenOnboarding', false);
    await widget.prefs.remove('setupSkipped');
    if (!mounted) return;

    final onReplayOnboarding = widget.onReplayOnboarding;
    if (onReplayOnboarding != null) {
      await onReplayOnboarding();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Onboarding will play on next launch.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: StreamBuilder<BluetoothAdapterState>(
            stream: context.read<BleRepository>().adapterState,
            builder: (context, adapterSnapshot) {
              return BlocConsumer<BleConnectionBloc, BleState>(
                listener: (context, state) async {
                  if (state is BleConnected) {
                    final deviceId = state.device.remoteId.str;
                    final onConnected = widget.onConnected;
                    if (onConnected != null) {
                      onConnected(deviceId);
                      return;
                    }
                    await widget.prefs.setString(
                      'rememberedDeviceId',
                      deviceId,
                    );
                    if (!context.mounted) return;
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const MainScreen()),
                    );
                  }
                },
                builder: (context, state) {
                  final status = _pairingStatusFor(state, adapterSnapshot.data);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    children: [
                      Row(
                        children: [
                          if (widget.onEnterDeveloperMode != null)
                            TextButton.icon(
                              onPressed: _enterDeveloperMode,
                              icon: const Icon(
                                Icons.developer_mode_rounded,
                                size: 18,
                              ),
                              label: const Text('Enter developer mode'),
                              style: TextButton.styleFrom(
                                foregroundColor: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          const Spacer(),
                          // Top-right escape hatch: use the app without a clock.
                          TextButton(
                            onPressed: _skipPairing,
                            style: TextButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('Skip'),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward_rounded, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _PairingHero(
                        status: status,
                        onPrimary: switch (status.primaryAction) {
                          _PairingPrimaryAction.search => _startScan,
                          _PairingPrimaryAction.settings => _openSystemSettings,
                          _PairingPrimaryAction.none => null,
                        },
                      ),
                      const SizedBox(height: 14),
                      _SetupShortcutActions(
                        onContinueWithoutClock: _skipPairing,
                        onReplayOnboarding: _replayOnboarding,
                      ),
                      const SizedBox(height: 22),
                      _NearbyClocksSection(
                        status: status,
                        onSearch: _startScan,
                        onOpenSettings: _openSystemSettings,
                        onContinueWithoutClock: _skipPairing,
                      ),
                      if (widget.onSetupDedicatedClock != null) ...[
                        const SizedBox(height: 22),
                        _NoClockSection(
                          onSetupDedicatedClock: widget.onSetupDedicatedClock!,
                        ),
                      ],
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  _PairingStatus _pairingStatusFor(
    BleState state,
    BluetoothAdapterState? adapterState,
  ) {
    final scheme = Theme.of(context).colorScheme;
    if (_permissionRequestInFlight) {
      return _PairingStatus(
        stage: _PairingStage.checkingAccess,
        icon: Icons.lock_open_rounded,
        color: scheme.primary,
        eyebrow: 'Checking Access',
        title: 'Preparing Bluetooth',
        detail:
            'WakeGuard is checking the permissions needed to find your clock.',
        primaryLabel: null,
        primaryAction: _PairingPrimaryAction.none,
      );
    }

    if (_permissionIssue == _BluetoothPermissionIssue.bluetooth) {
      return _PairingStatus(
        stage: _PairingStage.permissionBlocked,
        icon: Icons.lock_rounded,
        color: scheme.error,
        eyebrow: 'Bluetooth Permission',
        title: 'Bluetooth access is needed',
        detail:
            'Allow Bluetooth access so WakeGuard can discover and pair with your clock.',
        primaryLabel: 'Open Settings',
        primaryAction: _PairingPrimaryAction.settings,
      );
    }

    if (_permissionIssue == _BluetoothPermissionIssue.location) {
      return _PairingStatus(
        stage: _PairingStage.permissionBlocked,
        icon: Icons.location_on_rounded,
        color: AppColors.warning,
        eyebrow: 'Android Permission',
        title: 'Location access is needed',
        detail:
            'Android requires location permission for nearby Bluetooth scanning.',
        primaryLabel: 'Open Settings',
        primaryAction: _PairingPrimaryAction.settings,
      );
    }

    if (adapterState == BluetoothAdapterState.off ||
        adapterState == BluetoothAdapterState.turningOff) {
      return _PairingStatus(
        stage: _PairingStage.bluetoothOff,
        icon: Icons.bluetooth_disabled_rounded,
        color: scheme.error,
        eyebrow: 'Bluetooth Off',
        title: 'Turn on Bluetooth',
        detail:
            'WakeGuard needs Bluetooth on to find your physical clock nearby.',
        primaryLabel: 'Open Settings',
        primaryAction: _PairingPrimaryAction.settings,
      );
    }

    if (adapterState == BluetoothAdapterState.unauthorized ||
        adapterState == BluetoothAdapterState.unavailable) {
      return _PairingStatus(
        stage: _PairingStage.bluetoothOff,
        icon: Icons.bluetooth_disabled_rounded,
        color: scheme.error,
        eyebrow: 'Bluetooth Unavailable',
        title: 'Bluetooth is not available',
        detail:
            'Check Bluetooth permissions and device settings, then search again.',
        primaryLabel: 'Open Settings',
        primaryAction: _PairingPrimaryAction.settings,
      );
    }

    if (adapterState == BluetoothAdapterState.turningOn) {
      return _PairingStatus(
        stage: _PairingStage.checkingAccess,
        icon: Icons.bluetooth_searching_rounded,
        color: scheme.primary,
        eyebrow: 'Bluetooth Starting',
        title: 'Bluetooth is turning on',
        detail:
            'Keep the clock nearby. Search will work once Bluetooth is ready.',
        primaryLabel: null,
        primaryAction: _PairingPrimaryAction.none,
      );
    }

    if (state is BleConnecting) {
      return _PairingStatus(
        stage: _PairingStage.connecting,
        icon: Icons.bluetooth_connected_rounded,
        color: scheme.primary,
        eyebrow: 'Clock Found',
        title: 'Connecting to WakeGuard',
        detail:
            'The app found your clock and is setting up the connection now.',
        primaryLabel: null,
        primaryAction: _PairingPrimaryAction.none,
      );
    }

    if (state is BleScanning) {
      return _PairingStatus(
        stage: _PairingStage.searching,
        icon: Icons.radar_rounded,
        color: scheme.primary,
        eyebrow: 'Searching Nearby',
        title: 'Looking for your clock',
        detail:
            'Keep your WakeGuard clock powered on and within a few feet of this phone.',
        primaryLabel: 'Searching...',
        primaryAction: _PairingPrimaryAction.none,
      );
    }

    if (state is BleScanTimedOut) {
      return _PairingStatus(
        stage: _PairingStage.timedOut,
        icon: Icons.search_off_rounded,
        color: AppColors.warning,
        eyebrow: 'No Clock Found',
        title: 'We could not find your clock',
        detail:
            'Make sure the clock is powered on, close to this phone, and ready to pair.',
        primaryLabel: 'Search Again',
        primaryAction: _PairingPrimaryAction.search,
      );
    }

    return _PairingStatus(
      stage: _PairingStage.ready,
      icon: Icons.settings_input_antenna_rounded,
      color: scheme.primary,
      eyebrow: 'Ready to Pair',
      title: 'Connect your WakeGuard clock',
      detail:
          'Sync alarms, timers, display settings, and time calibration with your physical clock.',
      primaryLabel: 'Search For Clock',
      primaryAction: _PairingPrimaryAction.search,
    );
  }
}

enum _BluetoothPermissionIssue { none, bluetooth, location }

enum _PairingStage {
  ready,
  checkingAccess,
  permissionBlocked,
  bluetoothOff,
  searching,
  connecting,
  timedOut,
}

enum _PairingPrimaryAction { none, search, settings }

class _PairingStatus {
  final _PairingStage stage;
  final IconData icon;
  final Color color;
  final String eyebrow;
  final String title;
  final String detail;
  final String? primaryLabel;
  final _PairingPrimaryAction primaryAction;

  const _PairingStatus({
    required this.stage,
    required this.icon,
    required this.color,
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.primaryLabel,
    required this.primaryAction,
  });

  bool get animates =>
      stage == _PairingStage.searching ||
      stage == _PairingStage.connecting ||
      stage == _PairingStage.checkingAccess;
}

class _SetupShortcutActions extends StatelessWidget {
  final VoidCallback onContinueWithoutClock;
  final VoidCallback onReplayOnboarding;

  const _SetupShortcutActions({
    required this.onContinueWithoutClock,
    required this.onReplayOnboarding,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 24,
      shadows: wakeCardShadow(context),
      child: Column(
        children: [
          WakeSecondaryButton(
            label: 'Continue Without Clock',
            icon: Icons.arrow_forward_rounded,
            onPressed: onContinueWithoutClock,
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: onReplayOnboarding,
            icon: const Icon(Icons.replay_rounded, size: 17),
            label: const Text('Replay onboarding'),
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(42),
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PairingHero extends StatefulWidget {
  final _PairingStatus status;
  final VoidCallback? onPrimary;

  const _PairingHero({required this.status, required this.onPrimary});

  @override
  State<_PairingHero> createState() => _PairingHeroState();
}

class _PairingHeroState extends State<_PairingHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = widget.status;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final compact = MediaQuery.sizeOf(context).height < 700;
    final buttonLabel = status.primaryLabel;

    return GlassCard(
      padding: EdgeInsets.fromLTRB(22, compact ? 18 : 24, 22, 22),
      borderRadius: 30,
      shadows: wakeCardShadow(context),
      child: Column(
        children: [
          _PairingSignalMark(
            animation: _pulse,
            color: status.color,
            active: status.animates && !reduceMotion,
            dimension: compact ? 118 : 152,
            logoSize: compact ? 72 : 88,
          ),
          SizedBox(height: compact ? 12 : 18),
          WakeStatusPill(
            label: status.eyebrow,
            icon: status.icon,
            color: status.color,
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            status.title,
            textAlign: TextAlign.center,
            style:
                (compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                      height: 1.05,
                    ),
          ),
          const SizedBox(height: 10),
          Text(
            status.detail,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.38,
              color: scheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: compact ? 12 : 18),
          _PairingSteps(compact: compact),
          if (buttonLabel != null) ...[
            SizedBox(height: compact ? 14 : 20),
            WakePrimaryButton(
              label: buttonLabel,
              icon: status.primaryAction == _PairingPrimaryAction.settings
                  ? Icons.settings_rounded
                  : Icons.bluetooth_searching_rounded,
              onPressed: widget.onPrimary,
            ),
          ] else if (status.animates) ...[
            SizedBox(height: compact ? 14 : 20),
            LinearProgressIndicator(
              minHeight: 3,
              borderRadius: BorderRadius.circular(999),
              color: status.color,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ],
        ],
      ),
    );
  }
}

class _PairingSignalMark extends StatelessWidget {
  final Animation<double> animation;
  final Color color;
  final bool active;
  final double dimension;
  final double logoSize;

  const _PairingSignalMark({
    required this.animation,
    required this.color,
    required this.active,
    required this.dimension,
    required this.logoSize,
  });

  @override
  Widget build(BuildContext context) {
    Widget buildMark(double progress) {
      return SizedBox.square(
        dimension: dimension,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size.square(dimension),
              painter: _PairingPulsePainter(
                progress: progress,
                color: color,
                active: active,
              ),
            ),
            WakeLogoMark(size: logoSize),
          ],
        ),
      );
    }

    if (!active) return buildMark(0.42);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) => buildMark(animation.value),
      ),
    );
  }
}

class _PairingPulsePainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool active;

  const _PairingPulsePainter({
    required this.progress,
    required this.color,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final baseRadius = size.shortestSide * 0.31;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.08);

    canvas.drawCircle(center, baseRadius + 10, fillPaint);

    for (var i = 0; i < 3; i++) {
      final offset = active ? (progress + (i * 0.32)) % 1.0 : i / 3;
      final radius = baseRadius + 14 + (offset * 31);
      final alpha = active ? (1 - offset) * 0.22 : 0.07;
      ringPaint.color = color.withValues(alpha: alpha.clamp(0.04, 0.22));
      canvas.drawCircle(center, radius, ringPaint);
    }

    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: active ? 0.46 : 0.18);
    final rect = Rect.fromCircle(center: center, radius: baseRadius + 22);
    final start = (progress * math.pi * 2) - math.pi / 2;
    canvas.drawArc(rect, start, math.pi * 0.52, false, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _PairingPulsePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.active != active;
  }
}

class _PairingSteps extends StatelessWidget {
  final bool compact;

  const _PairingSteps({required this.compact});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _PairingStep(
            icon: Icons.power_settings_new_rounded,
            label: 'Power on',
            compact: compact,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _PairingStep(
            icon: Icons.phone_iphone_rounded,
            label: 'Keep close',
            compact: compact,
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _PairingStep(
            icon: Icons.bluetooth_connected_rounded,
            label: 'Auto pair',
            compact: compact,
          ),
        ),
      ],
    );
  }
}

class _PairingStep extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool compact;

  const _PairingStep({
    required this.icon,
    required this.label,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: compact ? 50 : 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: GlassTheme.of(context).stroke),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: compact ? 16 : 18, color: scheme.primary),
          SizedBox(height: compact ? 3 : 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyClocksSection extends StatelessWidget {
  final _PairingStatus status;
  final VoidCallback onSearch;
  final VoidCallback onOpenSettings;
  final VoidCallback onContinueWithoutClock;

  const _NearbyClocksSection({
    required this.status,
    required this.onSearch,
    required this.onOpenSettings,
    required this.onContinueWithoutClock,
  });

  @override
  Widget build(BuildContext context) {
    final child = switch (status.stage) {
      _PairingStage.permissionBlocked || _PairingStage.bluetoothOff =>
        _BlockedPairingCard(status: status, onOpenSettings: onOpenSettings),
      _PairingStage.searching => _SearchingClockCard(status: status),
      _PairingStage.connecting => _FoundClockCard(status: status),
      _PairingStage.timedOut => _TimeoutRecoveryCard(
        onSearch: onSearch,
        onContinueWithoutClock: onContinueWithoutClock,
      ),
      _ => _ReadyClockChecklist(onSearch: onSearch),
    };

    return WakeSection(
      title: 'Nearby Clock',
      subtitle: 'WakeGuard connects automatically once your clock is found.',
      child: child,
    );
  }
}

class _SearchingClockCard extends StatelessWidget {
  final _PairingStatus status;

  const _SearchingClockCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 40,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: status.color,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scanning for WakeGuard',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Keep the clock awake and near this phone.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FoundClockCard extends StatelessWidget {
  final _PairingStatus status;

  const _FoundClockCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: status.color.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.bluetooth_connected_rounded, color: status.color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WakeGuard Clock found',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Finishing the connection and preparing sync.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockedPairingCard extends StatelessWidget {
  final _PairingStatus status;
  final VoidCallback onOpenSettings;

  const _BlockedPairingCard({
    required this.status,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(status.icon, color: status.color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pairing is paused',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status.detail,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          WakeSecondaryButton(
            label: 'Open Settings',
            icon: Icons.settings_rounded,
            onPressed: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _ReadyClockChecklist extends StatelessWidget {
  final VoidCallback onSearch;

  const _ReadyClockChecklist({required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Column(
        children: [
          const _ChecklistRow(
            icon: Icons.power_settings_new_rounded,
            title: 'Clock powered on',
            detail: 'WakeGuard should be awake and ready to advertise.',
          ),
          const SizedBox(height: 12),
          const _ChecklistRow(
            icon: Icons.near_me_rounded,
            title: 'Phone nearby',
            detail: 'Keep this phone within a few feet while pairing.',
          ),
          const SizedBox(height: 12),
          const _ChecklistRow(
            icon: Icons.bluetooth_rounded,
            title: 'Bluetooth enabled',
            detail: 'The app will connect automatically when found.',
          ),
          const SizedBox(height: 16),
          WakeSecondaryButton(
            label: 'Search Again',
            icon: Icons.search_rounded,
            onPressed: onSearch,
          ),
        ],
      ),
    );
  }
}

class _TimeoutRecoveryCard extends StatelessWidget {
  final VoidCallback onSearch;
  final VoidCallback onContinueWithoutClock;

  const _TimeoutRecoveryCard({
    required this.onSearch,
    required this.onContinueWithoutClock,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.search_off_rounded, color: AppColors.warning),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Try these before searching again',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _ChecklistRow(
            icon: Icons.power_rounded,
            title: 'Wake the clock',
            detail: 'Make sure the WakeGuard clock is powered on.',
          ),
          const SizedBox(height: 12),
          const _ChecklistRow(
            icon: Icons.bluetooth_searching_rounded,
            title: 'Move closer',
            detail: 'Place the phone next to the clock for pairing.',
          ),
          const SizedBox(height: 12),
          const _ChecklistRow(
            icon: Icons.restart_alt_rounded,
            title: 'Restart pairing',
            detail: 'If needed, power-cycle the clock and search again.',
          ),
          const SizedBox(height: 16),
          WakePrimaryButton(
            label: 'Search Again',
            icon: Icons.search_rounded,
            onPressed: onSearch,
          ),
          const SizedBox(height: 10),
          WakeSecondaryButton(
            label: 'Continue Without Clock',
            icon: Icons.arrow_forward_rounded,
            onPressed: onContinueWithoutClock,
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;

  const _ChecklistRow({
    required this.icon,
    required this.title,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: scheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.32,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Escape hatch for users with no hardware clock: turn this device into a
/// standby Dedicated Clock (Beta) instead of pairing.
class _NoClockSection extends StatelessWidget {
  final VoidCallback onSetupDedicatedClock;

  const _NoClockSection({required this.onSetupDedicatedClock});

  @override
  Widget build(BuildContext context) {
    return WakeSection(
      title: 'No clock to pair?',
      subtitle:
          'Use this phone (or a spare one) as a standby bedside clock instead. '
          'Best-effort — the hardware clock is the tamper-proof one.',
      child: WakeSecondaryButton(
        label: 'Use this phone as a clock (Beta)',
        icon: Icons.phonelink_ring_rounded,
        onPressed: onSetupDedicatedClock,
      ),
    );
  }
}
