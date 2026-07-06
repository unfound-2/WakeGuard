import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/glass.dart';
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
    final primary = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: GlassBackground(
        child: SafeArea(
          child: Stack(
            children: [
              if (widget.onEnterDeveloperMode != null)
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: TextButton.icon(
                      onPressed: widget.onEnterDeveloperMode,
                      icon: const Icon(Icons.developer_mode_rounded, size: 18),
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
                ),
              Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 128,
                        height: 128,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              primary.withValues(alpha: 0.28),
                              primary.withValues(alpha: 0.04),
                            ],
                          ),
                          border: Border.all(
                            color: primary.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Icon(
                          Icons.watch_rounded,
                          size: 60,
                          color: primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      'WakeGuard',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Pair your clock to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 44),
                    BlocConsumer<BleConnectionBloc, BleState>(
                      listener: (context, state) async {
                        if (state is BleConnected) {
                          await widget.prefs.setString(
                            'rememberedDeviceId',
                            state.device.remoteId.str,
                          );
                          if (!context.mounted) return;
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MainScreen(),
                            ),
                          );
                        }
                      },
                      builder: (context, state) {
                        if (state is BleScanning || state is BleConnecting) {
                          return GlassCard(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Column(
                              children: [
                                CircularProgressIndicator(color: primary),
                                const SizedBox(height: 16),
                                Text(
                                  'Searching for your clock…',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return SizedBox(
                          height: 60,
                          child: ElevatedButton.icon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.bluetooth_searching_rounded),
                            label: const Text(
                              'SEARCH FOR CLOCK',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
