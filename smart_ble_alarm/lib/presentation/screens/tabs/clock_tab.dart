import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../../main.dart' as app_main;
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/ble_bloc/ble_event.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';

class ClockTab extends StatelessWidget {
  const ClockTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
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
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 24, top: 16),
              child: Text('CLOCK SETTINGS', style: TextStyle(color: AppColors.neonBlue, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 18)),
            ),
            _buildSectionHeader('DISPLAY'),
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                final sleepStart = TimeOfDay(hour: settingsState.sleepStartHour, minute: settingsState.sleepStartMinute);
                final sleepEnd = TimeOfDay(hour: settingsState.sleepEndHour, minute: settingsState.sleepEndMinute);

                return _buildCard([
                  _buildSwitchTile(
                    title: '24-Hour (Military Time)',
                    subtitle: 'Use 24-hour time format everywhere',
                    value: settingsState.is24HourTime,
                    onChanged: (val) => context.read<SettingsBloc>().add(Toggle24HourTimeEvent(val)),
                    icon: Icons.access_time,
                  ),
                  _buildSwitchTile(
                    title: 'Auto-Dim Display',
                    subtitle: 'Uses light sensor to turn off backlight in darkness',
                    icon: Icons.brightness_auto,
                    value: settingsState.autoDim,
                    onChanged: (val) {
                      context.read<SettingsBloc>().add(
                        UpdateClockConfigEvent(val, sleepStart.hour, sleepStart.minute, sleepEnd.hour, sleepEnd.minute)
                      );
                    },
                  ),
                  _buildListTile(
                    title: 'Sleep Schedule',
                    subtitle: 'Display OFF from ${sleepStart.format(context)} to ${sleepEnd.format(context)}',
                    icon: Icons.schedule,
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textSecondary),
                    onTap: () async {
                      final start = await showTimePicker(
                        context: context, 
                        initialTime: sleepStart,
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: settingsState.is24HourTime),
                            child: child!,
                          );
                        },
                      );
                      if (start == null) return;
                      if (!context.mounted) return;
                      
                      final end = await showTimePicker(
                        context: context, 
                        initialTime: sleepEnd,
                        builder: (context, child) {
                          return MediaQuery(
                            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: settingsState.is24HourTime),
                            child: child!,
                          );
                        },
                      );
                      if (end == null) return;
                      if (!context.mounted) return;
                      
                      context.read<SettingsBloc>().add(
                        UpdateClockConfigEvent(settingsState.autoDim, start.hour, start.minute, end.hour, end.minute)
                      );
                    },
                  ),
                ]);
              }
            ),
            
            _buildSectionHeader('BLUETOOTH'),
            BlocBuilder<BleConnectionBloc, BleState>(
              builder: (context, bleState) {
                String status = 'Disconnected';
                Color color = AppColors.error;
                if (bleState is BleConnected) {
                  status = 'Connected to ${bleState.device.platformName}';
                  color = AppColors.success;
                } else if (bleState is BleConnecting || bleState is BleScanning) {
                  status = 'Connecting...';
                  color = AppColors.primaryOrange;
                }

                return _buildCard([
                  _buildListTile(
                    title: 'Connection Status',
                    subtitle: status,
                    icon: Icons.bluetooth,
                    trailing: Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                  if (bleState is BleDisconnected)
                    _buildListTile(
                      title: 'Reconnect Device',
                      icon: Icons.bluetooth_searching,
                      onTap: () => context.read<BleConnectionBloc>().add(StartScanEvent()),
                    ),
                  if (bleState is BleConnected)
                    _buildListTile(
                      title: 'Forget Device',
                      icon: Icons.bluetooth_disabled,
                      titleColor: AppColors.error,
                      onTap: () async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.remove('rememberedDeviceId');
                        if (!context.mounted) return;
                        app_main.main();
                      },
                    ),
                ]);
              },
            ),

          ],
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
}
