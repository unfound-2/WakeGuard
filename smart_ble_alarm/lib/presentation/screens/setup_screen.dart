import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/ble_bloc/ble_event.dart';
import 'main_screen.dart';

class SetupScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const SetupScreen({super.key, required this.prefs});

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
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0F111A)
                        : const Color(0xFFF3F4F6)),
                    Colors.black,
                  ]
                : [
                    (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0F111A)
                        : const Color(0xFFF3F4F6)),
                    Colors.white,
                  ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: 'WakeGuard logo',
                  image: true,
                  child: Container(
                    width: 112,
                    height: 112,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(35),
                          blurRadius: 22,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/branding/wakeguard_logo.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'WakeGuard',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Pair your clock to get started.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF8B9BB4)
                        : const Color(0xFF6B7280)),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 48),
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
                        MaterialPageRoute(builder: (_) => const MainScreen()),
                      );
                    }
                  },
                  builder: (context, state) {
                    if (state is BleScanning || state is BleConnecting) {
                      return Column(
                        children: [
                          CircularProgressIndicator(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Searching...',
                            style: TextStyle(
                              color:
                                  (Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const Color(0xFF8B9BB4)
                                  : const Color(0xFF6B7280)),
                            ),
                          ),
                        ],
                      );
                    }
                    return ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () {
                        _startScan();
                      },
                      child: const Text(
                        'SEARCH FOR CLOCK',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
