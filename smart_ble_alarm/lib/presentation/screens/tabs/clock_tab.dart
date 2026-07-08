import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/ble/clock_sync.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/wake_widgets.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../../data/datasources/secure_key_datasource.dart';
import '../../../domain/usecases/print_qr_code.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_event.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../blocs/timer_cubit/countdown_timer_cubit.dart';
import '../setup_screen.dart';

/// The WakeGuard Clock device page: everything that manages the physical clock —
/// the Bluetooth link, synchronization, and the printed backup-code path. Opened
/// as a sub-page from Settings (the clock's *display* customization lives on the
/// Display tab; general app preferences live in Settings).
class ClockDeviceScreen extends StatefulWidget {
  const ClockDeviceScreen({super.key});

  @override
  State<ClockDeviceScreen> createState() => _ClockDeviceScreenState();
}

class _ClockDeviceScreenState extends State<ClockDeviceScreen> {
  @override
  void initState() {
    super.initState();
    loadLastClockSync();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('WakeGuard Clock'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GlassBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            children: [
              _buildDeviceHeader(),
              const SizedBox(height: 24),
              _buildBluetoothSection(),
              const SizedBox(height: 24),
              _buildSyncSection(),
              const SizedBox(height: 24),
              _buildBackupSection(),
            ],
          ),
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
                ValueListenableBuilder<bool>(
                  valueListenable: clockSyncInProgress,
                  builder: (context, syncing, _) => WakePrimaryButton(
                    label: syncing
                        ? 'Synchronizing…'
                        : 'Sync Time, Alarms & Settings',
                    icon: Icons.sync_rounded,
                    onPressed: (connected && !syncing)
                        ? () => syncConnectedClock(
                            context,
                            bleState.device,
                            showSuccess: true,
                          )
                        : null,
                  ),
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
          'One printed code that dismisses any protected alarm — for when '
          'object verification is unavailable.',
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
                        'One signed code works for every protected alarm. '
                        'Print it, keep it somewhere safe, and scan it on the '
                        'ringing screen if you can\'t complete the wake '
                        'challenge.',
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
              label: 'Print Backup Code',
              icon: Icons.print_rounded,
              onPressed: () => _printBackupCode(context),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the OS print dialog for the single app-wide backup QR code (works for
  /// every protected alarm — see [SecureKeyDatasource]).
  Future<void> _printBackupCode(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final usecase = PrintQrCodeUseCase(
      secureKeyDatasource: SecureKeyDatasource(),
    );
    try {
      await usecase.execute();
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Unable to open the print dialog.'),
          backgroundColor: scheme.error,
        ),
      );
    }
  }
}
