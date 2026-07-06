import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/wake_widgets.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/ble_bloc/ble_event.dart';
import 'main_screen.dart';

class SetupScreen extends StatefulWidget {
  final SharedPreferences prefs;

  /// Temporary hook: swaps the app onto the simulated clock so the connected
  /// UI can be explored without pairing real hardware. When null the
  /// developer-mode button is hidden.
  final VoidCallback? onEnterDeveloperMode;

  const SetupScreen({
    super.key,
    required this.prefs,
    this.onEnterDeveloperMode,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    try {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    } catch (_) {
      // Permission plugins are unavailable in widget tests and some desktop runs.
    }

    if (!mounted) return;
    context.read<BleConnectionBloc>().add(StartScanEvent());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: BlocConsumer<BleConnectionBloc, BleState>(
            listener: (context, state) async {
              if (state is BleConnected) {
                await widget.prefs.setString(
                  'rememberedDeviceId',
                  state.device.remoteId.str,
                );
                if (!context.mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                );
              }
            },
            builder: (context, state) {
              final scanning = state is BleScanning || state is BleConnecting;
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (widget.onEnterDeveloperMode != null)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: widget.onEnterDeveloperMode,
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
                    ),
                  const _PairingHeader(),
                  const SizedBox(height: 22),
                  _StatusCard(scanning: scanning),
                  const SizedBox(height: 22),
                  _ActionCard(scanning: scanning, onSearch: _startScan),
                  const SizedBox(height: 22),
                  _NearbyClocksSection(scanning: scanning),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Hero for the pairing screen: logo tile, big headline, muted lead — mirrors
/// the native PairingView header.
class _PairingHeader extends StatelessWidget {
  const _PairingHeader();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const WakeLogoMark(size: 76),
        const SizedBox(height: 16),
        Text(
          'Connect WakeGuard',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Pair with your physical clock to synchronize alarms, timers, '
          'display settings, and time calibration.',
          style: TextStyle(
            fontSize: 16,
            height: 1.4,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Live connection status on a glass card: icon, title, detail, and a spinner
/// while scanning or connecting.
class _StatusCard extends StatelessWidget {
  final bool scanning;

  const _StatusCard({required this.scanning});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final IconData symbol;
    final Color color;
    final String title;
    final String detail;
    if (scanning) {
      symbol = Icons.sync_rounded;
      color = colorScheme.primary;
      title = 'Searching';
      detail = 'Looking for your WakeGuard clock nearby…';
    } else {
      symbol = Icons.settings_input_antenna_rounded;
      color = colorScheme.onSurfaceVariant;
      title = 'Ready to pair';
      detail = 'Power on your clock and tap Search For Clock.';
    }

    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(symbol, size: 26, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (scanning) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Primary search action on a glass card, disabled visually while a scan is in
/// flight — matching the native PairingView action card.
class _ActionCard extends StatelessWidget {
  final bool scanning;
  final VoidCallback onSearch;

  const _ActionCard({required this.scanning, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Opacity(
        opacity: scanning ? 0.72 : 1,
        child: WakePrimaryButton(
          label: scanning ? 'Searching…' : 'Search For Clock',
          icon: Icons.bluetooth_searching_rounded,
          onPressed: scanning ? null : onSearch,
        ),
      ),
    );
  }
}

/// While idle, shows the "no clocks yet" empty state; while scanning, shows a
/// glass "searching" tile. The BLE bloc auto-connects to the first matching
/// clock (there is no user-selectable discovered-device list in state), so this
/// reflects the live scan rather than a device roster.
class _NearbyClocksSection extends StatelessWidget {
  final bool scanning;

  const _NearbyClocksSection({required this.scanning});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return WakeSection(
      title: 'Nearby Clocks',
      subtitle: 'Keep your WakeGuard clock powered on and nearby while searching.',
      child: scanning
          ? GlassCard(
              padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
              shadows: wakeCardShadow(context),
              child: Column(
                children: [
                  CircularProgressIndicator(color: colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Searching for your clock…',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The app connects automatically once it finds your clock.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                const WakeEmptyState(
                  title: 'No clocks yet',
                  message:
                      'Tap Search For Clock while your WakeGuard clock is '
                      'powered on and nearby.',
                  icon: Icons.settings_input_antenna_rounded,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppColors.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Bluetooth must be on to discover your clock.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
