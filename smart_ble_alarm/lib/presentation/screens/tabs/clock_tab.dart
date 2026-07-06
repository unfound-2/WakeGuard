import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/ble/clock_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/wake_widgets.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../domain/entities/alarm.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_event.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../item_scan_screen.dart';
import '../scanner_screen.dart';
import '../setup_screen.dart';

/// The Clock tab: everything that controls the physical WakeGuard clock —
/// display behaviour, the Bluetooth link, synchronization, and the printed
/// backup-code path. App preferences live in Settings; this tab is the
/// hardware's home (ported from the native ClockView).
class ClockTab extends StatefulWidget {
  const ClockTab({super.key});

  @override
  State<ClockTab> createState() => _ClockTabState();
}

class _ClockTabState extends State<ClockTab> {
  @override
  void initState() {
    super.initState();
    loadLastClockSync();
  }

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
          children: [
            Text(
              'Clock',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            Text(
              'Controls for the physical alarm clock',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            _buildDeviceHeader(),
            const SizedBox(height: 24),
            _buildDisplaySection(),
            const SizedBox(height: 24),
            _buildBluetoothSection(),
            const SizedBox(height: 24),
            _buildSyncSection(),
            const SizedBox(height: 24),
            _buildBackupSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceHeader() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        final connected = bleState is BleConnected;
        final name = connected && bleState.device.platformName.isNotEmpty
            ? bleState.device.platformName
            : 'WakeGuard Clock';
        return GlassCard(
          padding: const EdgeInsets.all(18),
          shadows: wakeCardShadow(context),
          child: Row(
            children: [
              const WakeLogoMark(size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      connected
                          ? 'Hardware controls are available.'
                          : 'Connect to apply controls to hardware.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              WakeStatusPill(
                label: connected ? 'Online' : 'Offline',
                icon: connected
                    ? Icons.check_circle_rounded
                    : Icons.wifi_off_rounded,
                color: connected ? AppColors.success : AppColors.warning,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDisplaySection() {
    return WakeSection(
      title: 'Display',
      subtitle: 'LCD behaviour on the physical clock.',
      child: BlocBuilder<SettingsBloc, SettingsState>(
        builder: (context, settings) {
          return GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            shadows: wakeCardShadow(context),
            child: Column(
              children: [
                WakeSettingsRow(
                  icon: Icons.brightness_auto_rounded,
                  title: 'Auto-Dim Display',
                  subtitle: 'Light sensor turns the backlight off in darkness',
                  trailing: Switch(
                    value: settings.autoDim,
                    onChanged: (val) => context.read<SettingsBloc>().add(
                      UpdateClockConfigEvent(
                        val,
                        settings.sleepStartHour,
                        settings.sleepStartMinute,
                        settings.sleepEndHour,
                        settings.sleepEndMinute,
                      ),
                    ),
                  ),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                WakeSettingsRow(
                  icon: Icons.bedtime_rounded,
                  title: 'Sleep Mode Start',
                  subtitle: 'Display turns off during these hours',
                  trailing: _timeChip(
                    settings.sleepStartHour,
                    settings.sleepStartMinute,
                    settings.is24HourTime,
                  ),
                  onTap: () => _pickSleepTime(context, true, settings),
                ),
                Divider(height: 1, color: Theme.of(context).dividerColor),
                WakeSettingsRow(
                  icon: Icons.wb_sunny_rounded,
                  title: 'Sleep Mode End',
                  subtitle: 'Display turns back on',
                  trailing: _timeChip(
                    settings.sleepEndHour,
                    settings.sleepEndMinute,
                    settings.is24HourTime,
                  ),
                  onTap: () => _pickSleepTime(context, false, settings),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _timeChip(int hour, int minute, bool is24Hour) {
    return Text(
      AlarmTimeUtils.formatTime(hour, minute, is24Hour: is24Hour),
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
        fontSize: 15,
      ),
    );
  }

  Future<void> _pickSleepTime(
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

  Widget _buildBluetoothSection() {
    return WakeSection(
      title: 'Bluetooth',
      subtitle: 'Pair, reconnect, or forget the clock connection.',
      child: BlocBuilder<BleConnectionBloc, BleState>(
        builder: (context, bleState) {
          final String statusTitle;
          final String statusDetail;
          final Color statusColor;
          if (bleState is BleConnected) {
            statusTitle = 'Connected';
            statusDetail = bleState.device.platformName.isEmpty
                ? 'Your clock is connected.'
                : '${bleState.device.platformName} is connected.';
            statusColor = AppColors.success;
          } else if (bleState is BleConnecting || bleState is BleScanning) {
            statusTitle = 'Connecting';
            statusDetail = 'Re-establishing the link to your clock…';
            statusColor = Theme.of(context).colorScheme.primary;
          } else {
            statusTitle = 'Disconnected';
            statusDetail =
                'Changes save locally and sync when the clock reconnects.';
            statusColor = AppColors.warning;
          }

          return GlassCard(
            padding: const EdgeInsets.all(18),
            shadows: wakeCardShadow(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.settings_input_antenna_rounded,
                      size: 24,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusTitle,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            statusDetail,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (bleState is BleDisconnected)
                  WakeSecondaryButton(
                    label: 'Reconnect Device',
                    icon: Icons.bluetooth_searching_rounded,
                    // Reconnect to the remembered clock specifically, rather
                    // than a generic rescan (which would clear the saved device
                    // and break auto-reconnect on the next app open).
                    onPressed: () =>
                        context.read<BleConnectionBloc>().add(ReconnectEvent()),
                  ),
                if (bleState is BleConnecting || bleState is BleScanning)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                if (bleState is BleConnected)
                  WakeSecondaryButton(
                    label: 'Forget Device',
                    icon: Icons.bluetooth_disabled_rounded,
                    onPressed: () => _forgetDevice(context),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _forgetDevice(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Forget this clock?'),
        content: const Text(
          'The app will disconnect and stop reconnecting automatically. '
          'Alarms already on the clock keep ringing on their own.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Forget',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Actually release the clock: disconnect and stop auto-reconnect before
    // forgetting the saved device.
    context.read<BleConnectionBloc>().add(ForgetDeviceEvent());
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('rememberedDeviceId');
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => SetupScreen(prefs: prefs)),
      (_) => false,
    );
  }

  Widget _buildSyncSection() {
    return WakeSection(
      title: 'Synchronization',
      subtitle: 'Keep phone state and hardware state aligned.',
      child: BlocBuilder<BleConnectionBloc, BleState>(
        builder: (context, bleState) {
          final connected = bleState is BleConnected;
          return GlassCard(
            padding: const EdgeInsets.all(18),
            shadows: wakeCardShadow(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlocBuilder<SettingsBloc, SettingsState>(
                  buildWhen: (prev, curr) =>
                      prev.is24HourTime != curr.is24HourTime,
                  builder: (context, settings) =>
                      ValueListenableBuilder<DateTime?>(
                        valueListenable: lastClockSync,
                        builder: (context, lastSync, _) => WakeValueRow(
                          title: 'Last sync',
                          value: lastSync == null
                              ? 'Never'
                              : AlarmTimeUtils.formatSyncTimestamp(
                                  lastSync,
                                  is24Hour: settings.is24HourTime,
                                ),
                        ),
                      ),
                ),
                const SizedBox(height: 12),
                BlocBuilder<AlarmBloc, AlarmState>(
                  builder: (context, alarmState) {
                    final total = alarmState.alarms.length;
                    final synced = alarmState.syncedAlarmCount;
                    return WakeValueRow(
                      title: 'Alarms on clock',
                      value: total == 0 ? 'None' : '$synced of $total synced',
                    );
                  },
                ),
                const SizedBox(height: 12),
                BlocBuilder<CountdownTimerCubit, List<CountdownTimer>>(
                  builder: (context, timers) => WakeValueRow(
                    title: 'Active timers',
                    value: timers.isEmpty ? 'None' : '${timers.length} running',
                  ),
                ),
                const SizedBox(height: 16),
                WakePrimaryButton(
                  label: 'Sync Time, Alarms & Settings',
                  icon: Icons.sync_rounded,
                  onPressed: connected
                      ? () => syncConnectedClock(
                          context,
                          bleState.device,
                          showSuccess: true,
                        )
                      : null,
                ),
                if (!connected) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Connect to the clock to sync.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBackupSection() {
    return WakeSection(
      title: 'Backup Code',
      subtitle:
          'Use printed codes only when object verification is unavailable.',
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.qr_code_rounded,
                  size: 42,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Secure Backup Code',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Each protected alarm has a signed printable code. '
                        'Print codes from the Alarms tab; scan one here to '
                        'dismiss a ringing alarm.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            WakePrimaryButton(
              label: 'Open Backup Scanner',
              icon: Icons.qr_code_scanner_rounded,
              onPressed: () => _openBackupScanner(context),
            ),
          ],
        ),
      ),
    );
  }

  void _openBackupScanner(BuildContext context) {
    final alarmState = context.read<AlarmBloc>().state;
    final ringingAlarmId = alarmState.ringingAlarmId;
    if (ringingAlarmId != null) {
      final ringing = alarmState.alarms.where((a) => a.id == ringingAlarmId);
      if (ringing.isNotEmpty) {
        _pushDismissal(context, ringing.first);
        return;
      }
    }

    final taskAlarms = alarmState.alarms.where((a) => a.qrRequired).toList();
    if (taskAlarms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No challenge-protected alarms are available.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }
    if (taskAlarms.length == 1) {
      _pushDismissal(context, taskAlarms.first);
      return;
    }

    final is24Hour = context.read<SettingsBloc>().state.is24HourTime;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Choose alarm',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            for (final alarm in taskAlarms)
              ListTile(
                leading: Icon(
                  alarm.usesItemScan
                      ? Icons.center_focus_strong
                      : Icons.qr_code,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  AlarmTimeUtils.formatTime(
                    alarm.hour,
                    alarm.minute,
                    is24Hour: is24Hour,
                  ),
                ),
                subtitle: Text(AlarmTimeUtils.formatDays(alarm.dayMask)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pushDismissal(context, alarm);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _pushDismissal(BuildContext context, Alarm alarm) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => alarm.usesItemScan
            ? ItemScanScreen(alarm: alarm)
            : ScannerScreen(alarmId: alarm.id),
      ),
    );
  }
}
