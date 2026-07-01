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
              ? [(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F111A) : const Color(0xFFF3F4F6)), Colors.black]
              : [(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F111A) : const Color(0xFFF3F4F6)), Colors.white],
        ),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 24, top: 16),
              child: Text('CLOCK SETTINGS', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 18)),
            ),
            _buildSectionHeader(context, 'DISPLAY'),
            BlocBuilder<SettingsBloc, SettingsState>(
              builder: (context, settingsState) {
                return _buildCard(context, [
                  _buildSwitchTile(
                    context: context,
                    title: '24-Hour (Military Time)',
                    subtitle: 'Use 24-hour format instead of AM/PM',
                    value: settingsState.is24HourTime,
                    onChanged: (val) {
                      context.read<SettingsBloc>().add(Toggle24HourTimeEvent(val));
                    },
                    icon: Icons.access_time,
                  ),
                  _buildSwitchTile(
                    context: context,
                    title: 'Auto-Dim Display',
                    subtitle: 'Uses light sensor to turn off backlight in darkness',
                    icon: Icons.brightness_auto,
                    value: settingsState.autoDim,
                    onChanged: (val) {
                      context.read<SettingsBloc>().add(
                        UpdateClockConfigEvent(val, settingsState.sleepStartHour, settingsState.sleepStartMinute, settingsState.sleepEndHour, settingsState.sleepEndMinute)
                      );
                    },
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  _buildListTile(
                    context: context,
                    title: 'Sleep Mode Start',
                    subtitle: 'Display will turn off during these hours',
                    icon: Icons.bedtime,
                    trailing: Text(_formatTime(settingsState.sleepStartHour, settingsState.sleepStartMinute), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                    onTap: () => _pickTime(context, true, settingsState),
                  ),
                  Divider(height: 1, color: Theme.of(context).dividerColor),
                  _buildListTile(
                    context: context,
                    title: 'Sleep Mode End',
                    subtitle: 'Display will turn back on',
                    icon: Icons.wb_sunny,
                    trailing: Text(_formatTime(settingsState.sleepEndHour, settingsState.sleepEndMinute), style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                    onTap: () => _pickTime(context, false, settingsState),
                  ),
                ]);
              }
            ),
            
            _buildSectionHeader(context, 'BLUETOOTH'),
            BlocBuilder<BleConnectionBloc, BleState>(
              builder: (context, bleState) {
                String status = 'Disconnected';
                Color color = Theme.of(context).colorScheme.error;
                if (bleState is BleConnected) {
                  status = 'Connected to ${bleState.device.platformName}';
                  color = AppColors.success;
                } else if (bleState is BleConnecting || bleState is BleScanning) {
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
                      width: 12, height: 12,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                  if (bleState is BleDisconnected)
                    _buildListTile(
                      context: context,
                      title: 'Reconnect Device',
                      icon: Icons.bluetooth_searching,
                      onTap: () => context.read<BleConnectionBloc>().add(StartScanEvent()),
                    ),
                  if (bleState is BleConnected)
                    _buildListTile(
                      context: context,
                      title: 'Forget Device',
                      icon: Icons.bluetooth_disabled,
                      titleColor: Theme.of(context).colorScheme.error,
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

  String _formatTime(int hour, int minute) {
    final time = TimeOfDay(hour: hour, minute: minute);
    return "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}";
  }

  Future<void> _pickTime(BuildContext context, bool isStart, SettingsState state) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: isStart ? state.sleepStartHour : state.sleepEndHour, minute: isStart ? state.sleepStartMinute : state.sleepEndMinute),
    );
    if (picked != null) {
      if (!context.mounted) return;
      context.read<SettingsBloc>().add(UpdateClockConfigEvent(
        state.autoDim,
        isStart ? picked.hour : state.sleepStartHour,
        isStart ? picked.minute : state.sleepStartMinute,
        !isStart ? picked.hour : state.sleepEndHour,
        !isStart ? picked.minute : state.sleepEndMinute
      ));
    }
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.only(left: 8, bottom: 8, top: 24),
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
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Theme.of(context).dividerColor, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: children,
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
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8B9BB4) : const Color(0xFF6B7280)), fontSize: 12)),
      secondary: Icon(icon, color: Theme.of(context).colorScheme.primary),
      value: value,
      activeThumbColor: Theme.of(context).colorScheme.primary,
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
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: titleColor ?? Theme.of(context).colorScheme.primary),
      title: Text(title, style: TextStyle(color: titleColor ?? Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null ? Text(subtitle, style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8B9BB4) : const Color(0xFF6B7280)), fontSize: 12)) : null,
      trailing: trailing ?? Icon(Icons.chevron_right, color: Theme.of(context).dividerColor),
      onTap: onTap,
    );
  }
}
