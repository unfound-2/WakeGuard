import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../../domain/repositories/ble_repository.dart';
import '../../main.dart' as app_main;

class SettingsScreen extends StatefulWidget {
  final bool isTab;
  const SettingsScreen({super.key, this.isTab = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('SETTINGS'),
        automaticallyImplyLeading: !widget.isTab,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark 
                ? [AppColors.background, Colors.black]
                : [AppColors.lightBackground, Colors.white],
          ),
        ),
        child: SafeArea(
          child: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settingsState) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader('APPEARANCE'),
                  _buildCard([
                    _buildListTile(
                      title: 'Theme',
                      subtitle: settingsState.themeString,
                      icon: Icons.dark_mode,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: () {
                        _showSelectionSheet(
                          context,
                          'Select Theme',
                          ['Light', 'Dark'],
                          settingsState.themeString,
                          (val) => context.read<SettingsBloc>().add(UpdateThemeEvent(val)),
                        );
                      },
                    ),
                    _buildListTile(
                      title: 'Accent Color',
                      subtitle: settingsState.accentColorString,
                      icon: Icons.color_lens,
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                      onTap: () {
                        _showSelectionSheet(
                          context,
                          'Select Accent Color',
                          ['Neon Orange', 'Cyber Cyan', 'Matrix Green', 'Neon Blue'],
                          settingsState.accentColorString,
                          (val) => context.read<SettingsBloc>().add(UpdateAccentColorEvent(val)),
                        );
                      },
                    ),
                    _buildSwitchTile(
                      title: 'Animations',
                      subtitle: 'Enable UI transitions and effects',
                      value: settingsState.animationsEnabled,
                      onChanged: (val) => context.read<SettingsBloc>().add(ToggleAnimationsEvent(val)),
                      icon: Icons.animation,
                    ),
                  ]),

                  _buildSectionHeader('GENERAL'),
                  _buildCard([
                    _buildListTile(
                      title: 'About',
                      icon: Icons.info_outline,
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: 'Smart BLE Alarm',
                        applicationVersion: '1.0.0 (Build 42)',
                      ),
                    ),
                    _buildListTile(title: 'App Version', subtitle: '1.0.0 (Build 42)', icon: Icons.verified),
                    _buildListTile(
                      title: 'Open Source Licenses',
                      icon: Icons.description_outlined,
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'Smart BLE Alarm',
                        applicationVersion: '1.0.0 (Build 42)',
                      ),
                    ),
                  ]),

                  _buildSectionHeader('ADVANCED'),
                  _buildCard([
                    _buildListTile(
                      title: 'Factory Reset Clock',
                      icon: Icons.factory,
                      titleColor: AppColors.error,
                      onTap: () => _showConfirmationDialog(
                        context,
                        'Factory Reset Clock',
                        'This will erase all alarms and settings on the physical clock hardware. This cannot be undone.',
                        () {
                          final bleState = context.read<BleConnectionBloc>().state;
                          if (bleState is BleConnected) {
                            final repo = context.read<BleRepository>();
                            // Delete all 10 alarms
                            for (int i = 0; i < 10; i++) {
                              try { repo.sendCommand(bleState.device, 0x03, [i]); } catch (_) {}
                            }
                            // Reset config to defaults
                            try { repo.sendCommand(bleState.device, 0x06, [1, 22, 0, 6, 0]); } catch (_) {}
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Factory reset commands sent to clock.')));
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Must be connected to physical clock to factory reset.')));
                          }
                        },
                      ),
                    ),
                    _buildListTile(
                      title: 'Reset Local Data',
                      icon: Icons.delete_forever,
                      titleColor: AppColors.error,
                      onTap: () => _showConfirmationDialog(
                        context,
                        'Reset Local Data',
                        'This will clear all saved preferences and cached data on your phone.',
                        () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          if (!context.mounted) return;
                          app_main.main();
                        },
                      ),
                    ),
                  ]),

                  _buildSectionHeader('ALARM PREFERENCES'),
                  _buildCard([
                    _buildSwitchTile(
                      title: 'Default Require QR Scan',
                      subtitle: 'New alarms require QR scan by default',
                      value: settingsState.defaultQrRequired,
                      onChanged: (val) => context.read<SettingsBloc>().add(ToggleDefaultQrRequiredEvent(val)),
                      icon: Icons.qr_code,
                    ),
                  ]),

                  _buildSectionHeader('NOTIFICATIONS & PERMISSIONS'),
                  _buildCard([
                    _buildPermissionTile(
                      title: 'Notification Permission',
                      icon: Icons.notifications,
                      permission: Permission.notification,
                    ),
                    _buildPermissionTile(
                      title: 'Bluetooth Permission',
                      icon: Icons.bluetooth_connected,
                      permission: Permission.bluetoothConnect,
                    ),
                    _buildPermissionTile(
                      title: 'Location Permission',
                      icon: Icons.location_on,
                      permission: Permission.location,
                    ),
                    _buildListTile(
                      title: 'Open System Settings',
                      icon: Icons.settings_applications,
                      onTap: () => openAppSettings(),
                    ),
                  ]),

                  const SizedBox(height: 100), // spacing for bottom bar
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 24),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppColors.neonBlue,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.surfaceHighlight, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
      ),
    );
  }

  void _showSelectionSheet(BuildContext context, String title, List<String> options, String currentValue, Function(String) onSelect) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
              ...options.map((option) => ListTile(
                    title: Text(option, style: TextStyle(color: currentValue == option ? AppColors.neonBlue : AppColors.textPrimary)),
                    trailing: currentValue == option ? const Icon(Icons.check, color: AppColors.neonBlue) : null,
                    onTap: () {
                      onSelect(option);
                      Navigator.pop(context);
                    },
                  )),
            ],
          ),
        );
      },
    );
  }

  void _showConfirmationDialog(BuildContext context, String title, String content, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.surface,
          title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
          content: Text(content, style: const TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onConfirm();
              },
              child: const Text('CONFIRM', style: TextStyle(color: AppColors.error)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildListTile({
    required String title,
    String? subtitle,
    required IconData icon,
    Widget? trailing,
    VoidCallback? onTap,
    Color? titleColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: titleColor ?? AppColors.primaryOrange),
      title: Text(title, style: TextStyle(color: titleColor ?? AppColors.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)) : null,
      trailing: trailing,
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      secondary: Icon(icon, color: AppColors.primaryOrange),
      value: value,
      activeThumbColor: AppColors.neonBlue,
      onChanged: onChanged,
    );
  }

  Widget _buildPermissionTile({
    required String title,
    required IconData icon,
    required Permission permission,
  }) {
    return FutureBuilder<PermissionStatus>(
      future: permission.status,
      builder: (context, snapshot) {
        bool isGranted = snapshot.data == PermissionStatus.granted;
        return _buildListTile(
          title: title,
          subtitle: isGranted ? 'Granted' : 'Denied / Unknown',
          icon: icon,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isGranted ? AppColors.success.withValues(alpha: 0.2) : AppColors.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isGranted ? AppColors.success : AppColors.error),
            ),
            child: Text(isGranted ? 'OK' : 'FIX', style: TextStyle(color: isGranted ? AppColors.success : AppColors.error, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          onTap: () async {
            if (!isGranted) {
              await permission.request();
              setState(() {}); // Trigger rebuild to update permission status visually
            }
          },
        );
      }
    );
  }
}
