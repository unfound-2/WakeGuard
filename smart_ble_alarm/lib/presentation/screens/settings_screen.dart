import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../../domain/repositories/ble_repository.dart';
import 'setup_screen.dart';
import 'dismissal_history_screen.dart';

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
      body: GlassBackground(
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
                      trailing: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onTap: () {
                        _showSelectionSheet(
                          context,
                          'Select Theme',
                          const ['System', 'Light', 'Dark'],
                          settingsState.themeString,
                          (val) => context.read<SettingsBloc>().add(
                            UpdateThemeEvent(val),
                          ),
                        );
                      },
                    ),
                    _buildListTile(
                      title: 'Accent Color',
                      subtitle: settingsState.accentColorString,
                      icon: Icons.color_lens,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _accentSwatch(
                            AppColors.accentFromString(
                              settingsState.accentColorString,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                      onTap: () {
                        _showSelectionSheet(
                          context,
                          'Select Accent Color',
                          AppColors.accentNames,
                          settingsState.accentColorString,
                          (val) => context.read<SettingsBloc>().add(
                            UpdateAccentColorEvent(val),
                          ),
                          swatches: true,
                        );
                      },
                    ),
                    _buildSwitchTile(
                      title: 'Animations',
                      subtitle: 'Enable UI transitions and effects',
                      value: settingsState.animationsEnabled,
                      onChanged: (val) => context.read<SettingsBloc>().add(
                        ToggleAnimationsEvent(val),
                      ),
                      icon: Icons.animation,
                    ),
                  ]),

                  _buildSectionHeader('TIME'),
                  _buildCard([
                    _buildSwitchTile(
                      title: '24-Hour Time',
                      subtitle: 'Use 24-hour format instead of AM/PM',
                      value: settingsState.is24HourTime,
                      onChanged: (val) => context.read<SettingsBloc>().add(
                        Toggle24HourTimeEvent(val),
                      ),
                      icon: Icons.access_time,
                    ),
                  ]),

                  _buildSectionHeader('ALARM PREFERENCES'),
                  _buildCard([
                    _buildSwitchTile(
                      title: 'Default Require QR Scan',
                      subtitle: 'New alarms require QR scan by default',
                      value: settingsState.defaultQrRequired,
                      onChanged: (val) => context.read<SettingsBloc>().add(
                        ToggleDefaultQrRequiredEvent(val),
                      ),
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
                      title: 'Bluetooth Scan Permission',
                      icon: Icons.bluetooth_searching,
                      permission: Permission.bluetoothScan,
                    ),
                    _buildPermissionTile(
                      title: 'Bluetooth Connect Permission',
                      icon: Icons.bluetooth_connected,
                      permission: Permission.bluetoothConnect,
                    ),
                    _buildPermissionTile(
                      title: 'Location Permission',
                      icon: Icons.location_on,
                      permission: Permission.locationWhenInUse,
                    ),
                    _buildListTile(
                      title: 'Open System Settings',
                      icon: Icons.settings_applications,
                      onTap: () => openAppSettings(),
                    ),
                  ]),

                  _buildSectionHeader('GENERAL'),
                  _buildCard([
                    _buildListTile(
                      title: 'Dismissal History',
                      subtitle: 'When alarms were dismissed',
                      icon: Icons.history,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DismissalHistoryScreen(),
                        ),
                      ),
                    ),
                    _buildListTile(
                      title: 'About',
                      subtitle: 'Version 1.0.0 (Build 42)',
                      icon: Icons.info_outline,
                      onTap: () => showAboutDialog(
                        context: context,
                        applicationName: 'WakeGuard',
                        applicationVersion: '1.0.0 (Build 42)',
                      ),
                    ),
                    _buildListTile(
                      title: 'Open Source Licenses',
                      icon: Icons.description_outlined,
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: 'WakeGuard',
                        applicationVersion: '1.0.0 (Build 42)',
                      ),
                    ),
                  ]),

                  _buildSectionHeader('ADVANCED'),
                  _buildCard([
                    _buildListTile(
                      title: 'Factory Reset Clock',
                      icon: Icons.factory,
                      titleColor: Theme.of(context).colorScheme.error,
                      onTap: () => _showConfirmationDialog(
                        context,
                        'Factory Reset Clock',
                        'This will erase all alarms and settings on the physical clock hardware. This cannot be undone.',
                        () async {
                          final bleState = context
                              .read<BleConnectionBloc>()
                              .state;
                          if (bleState is BleConnected) {
                            final repo = context.read<BleRepository>();
                            final alarmBloc = context.read<AlarmBloc>();
                            final settingsBloc = context.read<SettingsBloc>();
                            final localAlarmIds = alarmBloc.state.alarms
                                .map((alarm) => alarm.id)
                                .toSet();
                            final idsToDelete = {
                              ...localAlarmIds,
                              1,
                              2,
                              3,
                              4,
                              5,
                            };
                            for (final id in idsToDelete) {
                              try {
                                await repo.sendCommand(bleState.device, 0x03, [
                                  id & 0xFF,
                                ]);
                              } catch (_) {}
                            }
                            // Reset config to defaults
                            try {
                              await repo.sendCommand(bleState.device, 0x06, [
                                1,
                                22,
                                0,
                                6,
                                0,
                              ]);
                            } catch (_) {}
                            // Mirror those defaults into the app's own settings
                            // state so the Clock tab doesn't keep displaying the
                            // user's old (now-erased) sleep hours / auto-dim.
                            settingsBloc.add(
                              const UpdateClockConfigEvent(true, 22, 0, 6, 0),
                            );
                            for (final id in localAlarmIds) {
                              alarmBloc.add(
                                DeleteAlarmEvent(id, bleState.device),
                              );
                            }
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Factory reset commands sent to clock.',
                                ),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Must be connected to physical clock to factory reset.',
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                    _buildListTile(
                      title: 'Reset Local Data',
                      icon: Icons.delete_forever,
                      titleColor: Theme.of(context).colorScheme.error,
                      onTap: () => _showConfirmationDialog(
                        context,
                        'Reset Local Data',
                        'This will clear all saved preferences and cached data on your phone.',
                        () async {
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          if (!context.mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => SetupScreen(prefs: prefs),
                            ),
                            (_) => false,
                          );
                        },
                      ),
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
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.5,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GlassCard(
        borderRadius: 22,
        child: Material(
          color: Colors.transparent,
          child: Column(children: children),
        ),
      ),
    );
  }

  Widget _accentSwatch(Color color, {double size = 20}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
        ],
      ),
    );
  }

  void _showSelectionSheet(
    BuildContext context,
    String title,
    List<String> options,
    String currentValue,
    Function(String) onSelect, {
    bool swatches = false,
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              ...options.map(
                (option) => ListTile(
                  leading: swatches
                      ? _accentSwatch(AppColors.accentFromString(option))
                      : null,
                  title: Text(
                    option,
                    style: TextStyle(
                      color: currentValue == option
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: currentValue == option
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                  trailing: currentValue == option
                      ? Icon(
                          Icons.check,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    onSelect(option);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showConfirmationDialog(
    BuildContext context,
    String title,
    String content,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Text(
            title,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          content: Text(
            content,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'CANCEL',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                onConfirm();
              },
              child: Text(
                'CONFIRM',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
      leading: Icon(
        icon,
        color: titleColor ?? Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            )
          : null,
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
      title: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
      secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
      value: value,
      onChanged: onChanged,
    );
  }

  // Cached per-permission status futures so unrelated rebuilds (e.g. toggling
  // another setting) don't recreate them and flicker the chip red->green.
  final Map<Permission, Future<PermissionStatus>> _permissionFutures = {};

  Future<PermissionStatus> _permissionStatus(Permission permission) {
    return _permissionFutures[permission] ??= permission.status;
  }

  Widget _buildPermissionTile({
    required String title,
    required IconData icon,
    required Permission permission,
  }) {
    return FutureBuilder<PermissionStatus>(
      future: _permissionStatus(permission),
      builder: (context, snapshot) {
        bool isGranted = snapshot.data == PermissionStatus.granted;
        return _buildListTile(
          title: title,
          subtitle: isGranted ? 'Granted' : 'Denied / Unknown',
          icon: icon,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: isGranted
                  ? AppColors.success.withValues(alpha: 0.2)
                  : Theme.of(context).colorScheme.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isGranted
                    ? AppColors.success
                    : Theme.of(context).colorScheme.error,
              ),
            ),
            child: Text(
              isGranted ? 'OK' : 'FIX',
              style: TextStyle(
                color: isGranted
                    ? AppColors.success
                    : Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          onTap: () async {
            if (!isGranted) {
              await permission.request();
              if (!mounted) return;
              // Refresh only this permission's cached status, then rebuild.
              setState(
                () => _permissionFutures[permission] = permission.status,
              );
            }
          },
        );
      },
    );
  }
}
