import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/utils/alarm_time_utils.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/ble_bloc/ble_event.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import 'setup_screen.dart';

/// Display & connection settings for the physical clock. Reached from the
/// Settings tab ("Clock Settings"); previously lived in its own bottom-bar tab.
class ClockSettingsScreen extends StatelessWidget {
  const ClockSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('CLOCK SETTINGS')),
      body: GlassBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _buildSectionHeader(context, 'DISPLAY'),
              BlocBuilder<SettingsBloc, SettingsState>(
                builder: (context, settingsState) {
                  return _buildCard(context, [
                    _buildSwitchTile(
                      context: context,
                      title: 'Auto-Dim Display',
                      subtitle:
                          'Uses light sensor to turn off backlight in darkness',
                      icon: Icons.brightness_auto,
                      value: settingsState.autoDim,
                      onChanged: (val) {
                        context.read<SettingsBloc>().add(
                          UpdateClockConfigEvent(
                            val,
                            settingsState.sleepStartHour,
                            settingsState.sleepStartMinute,
                            settingsState.sleepEndHour,
                            settingsState.sleepEndMinute,
                          ),
                        );
                      },
                    ),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    _buildListTile(
                      context: context,
                      title: 'Sleep Mode Start',
                      subtitle: 'Display will turn off during these hours',
                      icon: Icons.bedtime,
                      trailing: Text(
                        _formatTime(
                          settingsState.sleepStartHour,
                          settingsState.sleepStartMinute,
                          settingsState.is24HourTime,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      onTap: () => _pickTime(context, true, settingsState),
                    ),
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                    _buildListTile(
                      context: context,
                      title: 'Sleep Mode End',
                      subtitle: 'Display will turn back on',
                      icon: Icons.wb_sunny,
                      trailing: Text(
                        _formatTime(
                          settingsState.sleepEndHour,
                          settingsState.sleepEndMinute,
                          settingsState.is24HourTime,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      onTap: () => _pickTime(context, false, settingsState),
                    ),
                  ]);
                },
              ),

              _buildSectionHeader(context, 'BLUETOOTH'),
              BlocBuilder<BleConnectionBloc, BleState>(
                builder: (context, bleState) {
                  String status = 'Disconnected';
                  Color color = Theme.of(context).colorScheme.error;
                  if (bleState is BleConnected) {
                    status = 'Connected to ${bleState.device.platformName}';
                    color = AppColors.success;
                  } else if (bleState is BleConnecting ||
                      bleState is BleScanning) {
                    status = 'Connecting...';
                    color = Theme.of(context).colorScheme.primary;
                  }

                  return _buildCard(context, [
                    _buildListTile(
                      context: context,
                      title: 'Connection Status',
                      subtitle: status,
                      icon: Icons.bluetooth,
                      trailing: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    if (bleState is BleDisconnected)
                      _buildListTile(
                        context: context,
                        title: 'Reconnect Device',
                        icon: Icons.bluetooth_searching,
                        // Reconnect to the remembered clock specifically, rather
                        // than a generic rescan (which would clear the saved
                        // device and break auto-reconnect on the next app open).
                        onTap: () => context.read<BleConnectionBloc>().add(
                          ReconnectEvent(),
                        ),
                      ),
                    if (bleState is BleConnected)
                      _buildListTile(
                        context: context,
                        title: 'Forget Device',
                        icon: Icons.bluetooth_disabled,
                        titleColor: Theme.of(context).colorScheme.error,
                        onTap: () async {
                          // Actually release the clock: disconnect and stop
                          // auto-reconnect before forgetting the saved device.
                          context.read<BleConnectionBloc>().add(
                            ForgetDeviceEvent(),
                          );
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.remove('rememberedDeviceId');
                          if (!context.mounted) return;
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => SetupScreen(prefs: prefs),
                            ),
                            (_) => false,
                          );
                        },
                      ),
                  ]);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(int hour, int minute, bool is24Hour) =>
      AlarmTimeUtils.formatTime(hour, minute, is24Hour: is24Hour);

  Future<void> _pickTime(
    BuildContext context,
    bool isStart,
    SettingsState state,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: isStart ? state.sleepStartHour : state.sleepEndHour,
        minute: isStart ? state.sleepStartMinute : state.sleepEndMinute,
      ),
      // Honour the app's own 24-hour setting rather than the OS locale so the
      // picker matches how times are shown everywhere else in the app.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(alwaysUse24HourFormat: state.is24HourTime),
        child: child!,
      ),
    );
    if (picked != null) {
      if (!context.mounted) return;
      context.read<SettingsBloc>().add(
        UpdateClockConfigEvent(
          state.autoDim,
          isStart ? picked.hour : state.sleepStartHour,
          isStart ? picked.minute : state.sleepStartMinute,
          !isStart ? picked.hour : state.sleepEndHour,
          !isStart ? picked.minute : state.sleepEndMinute,
        ),
      );
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
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

  Widget _buildCard(BuildContext context, List<Widget> children) {
    return GlassCard(
      borderRadius: 22,
      child: Material(
        color: Colors.transparent,
        child: Column(children: children),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
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

  Widget _buildListTile({
    required BuildContext context,
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
      trailing:
          trailing ??
          Icon(Icons.chevron_right, color: Theme.of(context).dividerColor),
      onTap: onTap,
    );
  }
}
