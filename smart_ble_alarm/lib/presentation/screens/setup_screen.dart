import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/challenge/wake_challenge_options.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/ble_bloc/ble_event.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
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

  void _showWakeObjectSheet(SettingsState settingsState) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Choose Wake Object',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              ...WakeChallengeOptions.suggestedObjects.map(
                (option) => ListTile(
                  title: Text(option),
                  trailing: settingsState.wakeObjectName == option
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    context.read<SettingsBloc>().add(
                      UpdateWakeObjectEvent(option),
                    );
                    Navigator.pop(sheetContext);
                  },
                ),
              ),
              ListTile(
                leading: Icon(
                  Icons.edit,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: const Text('Custom object'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCustomWakeObjectDialog(settingsState.wakeObjectName);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showCustomWakeObjectDialog(String currentValue) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Custom wake object'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Bathroom sink, coffee maker, medication...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context.read<SettingsBloc>().add(
                  UpdateWakeObjectEvent(controller.text),
                );
                Navigator.pop(dialogContext);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Widget _buildWakeObjectPicker() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return Material(
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => _showWakeObjectSheet(settingsState),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    Icons.center_focus_strong,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wake object',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          settingsState.wakeObjectName,
                          style: TextStyle(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xFF8B9BB4)
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x35000000),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          'assets/branding/wakeguard_logo.png',
                          width: 112,
                          height: 112,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
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
                  'Pair your clock and choose the object you will verify when the alarm rings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF8B9BB4)
                        : const Color(0xFF6B7280)),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 24),
                _buildWakeObjectPicker(),
                const SizedBox(height: 36),
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
