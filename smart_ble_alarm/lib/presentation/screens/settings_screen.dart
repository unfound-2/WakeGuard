import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/wake_widgets.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_event.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/history_cubit/dismissal_history_cubit.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import '../blocs/timer_cubit/countdown_timer_cubit.dart';
import 'dismissal_history_screen.dart';
import 'tabs/clock_tab.dart';

/// App preferences in the native WakeGuard SettingsView layout: profile
/// header, then Appearance / Time / Device / Wake Challenge / Notifications /
/// Data / General / Advanced sections on glass cards. The clock's Bluetooth,
/// sync, and backup-code controls open from the Device row (ClockDeviceScreen);
/// the clock's screen customization lives on the Display tab.
class SettingsScreen extends StatefulWidget {
  final bool isTab;

  /// Non-null only while the app runs on the simulated (developer-mode) clock.
  /// When provided, the Advanced section shows a button to leave the simulator
  /// and return to pairing a real clock.
  final VoidCallback? onExitDeveloperMode;

  /// Non-null only while a real clock is paired. When provided, the Advanced
  /// section shows "Unpair Device", which hands off to the app-level callback
  /// (in `main.dart`) that forgets the clock and restarts onboarding.
  final VoidCallback? onUnpairDevice;

  /// Non-null only when the user skipped pairing (no clock yet). When provided,
  /// the Advanced section shows "Connect a Clock", which returns to the pairing
  /// screen via the app-level callback in `main.dart`.
  final VoidCallback? onConnectClock;

  const SettingsScreen({
    super.key,
    this.isTab = false,
    this.onExitDeveloperMode,
    this.onUnpairDevice,
    this.onConnectClock,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<String> _themeOptions = ['System', 'Light', 'Dark'];

  @override
  Widget build(BuildContext context) {
    final body = GlassBackground(
      child: SafeArea(
        bottom: !widget.isTab,
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settings) {
            return ListView(
              padding: widget.isTab
                  ? const EdgeInsets.fromLTRB(20, 8, 20, 130)
                  : const EdgeInsets.fromLTRB(20, 8, 20, 40),
              children: [
                if (widget.isTab) ...[
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'Preferences for the WakeGuard app',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                _buildProfileCard(),
                const SizedBox(height: 24),
                _buildAppearanceSection(settings),
                const SizedBox(height: 24),
                _buildTimeSection(settings),
                const SizedBox(height: 24),
                _buildClockDeviceSection(),
                const SizedBox(height: 24),
                _buildChallengeSection(settings),
                const SizedBox(height: 24),
                _buildNotificationsSection(settings),
                const SizedBox(height: 24),
                _buildDataSection(),
                const SizedBox(height: 24),
                _buildGeneralSection(),
                const SizedBox(height: 24),
                _buildAdvancedSection(),
              ],
            );
          },
        ),
      ),
    );

    if (widget.isTab) return body;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Settings')),
      body: body,
    );
  }

  // ---- Profile ------------------------------------------------------------

  Widget _buildProfileCard() {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      shadows: wakeCardShadow(context),
      child: Row(
        children: [
          const WakeLogoMark(size: 62),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WakeGuard',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Bluetooth wake challenge companion',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Appearance ---------------------------------------------------------

  Widget _buildAppearanceSection(SettingsState settings) {
    final scheme = Theme.of(context).colorScheme;
    final selectedTheme = _themeOptions.contains(settings.themeString)
        ? settings.themeString
        : 'Dark';
    return WakeSection(
      title: 'Appearance',
      child: GlassCard(
        padding: const EdgeInsets.all(18),
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'System', label: Text('System')),
                ButtonSegment(value: 'Light', label: Text('Light')),
                ButtonSegment(value: 'Dark', label: Text('Dark')),
              ],
              selected: {selectedTheme},
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: scheme.primary,
                selectedForegroundColor: scheme.onPrimary,
                side: BorderSide(color: GlassTheme.of(context).stroke),
              ),
              onSelectionChanged: (selection) => context
                  .read<SettingsBloc>()
                  .add(UpdateThemeEvent(selection.first)),
            ),
            const SizedBox(height: 18),
            Text(
              'Accent color',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 14,
              runSpacing: 12,
              children: [
                for (final name in AppColors.accentNames)
                  _accentSwatch(
                    name,
                    AppColors.canonicalAccentName(
                          settings.accentColorString,
                        ) ==
                        name,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 17, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.animation_rounded,
              title: 'Animated controls',
              subtitle: 'Animate the day picker and use haptics when editing '
                  'alarms',
              trailing: Switch(
                value: settings.animationsEnabled,
                onChanged: (val) => context.read<SettingsBloc>().add(
                  ToggleAnimationsEvent(val),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accentSwatch(String name, bool selected) {
    final color = AppColors.accentFromString(name);
    return Tooltip(
      message: name,
      child: GestureDetector(
        onTap: () =>
            context.read<SettingsBloc>().add(UpdateAccentColorEvent(name)),
        child: Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 10,
                ),
              ],
            ),
            child: selected
                ? Icon(
                    Icons.check_rounded,
                    size: 18,
                    // Contrast the check against the swatch itself so it stays
                    // visible on light accents (Mint/Sky) and dark ones alike.
                    color:
                        ThemeData.estimateBrightnessForColor(color) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  // ---- Time ---------------------------------------------------------------

  Widget _buildTimeSection(SettingsState settings) {
    return WakeSection(
      title: 'Time',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            WakeSettingsRow(
              icon: Icons.access_time_rounded,
              title: '24-Hour Time',
              subtitle: 'Use 24-hour format instead of AM/PM',
              trailing: Switch(
                value: settings.is24HourTime,
                onChanged: (val) => context.read<SettingsBloc>().add(
                  Toggle24HourTimeEvent(val),
                ),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.update_rounded,
              title: 'Automatic Time Sync',
              subtitle: 'Push phone time to the clock on every connect',
              trailing: Switch(
                value: settings.autoTimeSync,
                onChanged: (val) => context.read<SettingsBloc>().add(
                  ToggleAutoTimeSyncEvent(val),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Clock device -------------------------------------------------------

  Widget _buildClockDeviceSection() {
    return WakeSection(
      title: 'Device',
      subtitle: 'Manage the physical WakeGuard clock.',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        shadows: wakeCardShadow(context),
        child: WakeSettingsRow(
          icon: Icons.watch_rounded,
          title: 'WakeGuard Clock',
          subtitle: 'Bluetooth connection, sync, and backup code',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ClockDeviceScreen()),
          ),
        ),
      ),
    );
  }

  // ---- Wake Challenge -----------------------------------------------------

  Widget _buildChallengeSection(SettingsState settings) {
    return WakeSection(
      title: 'Wake Challenge',
      subtitle: 'Set whether new alarms start with a wake challenge.',
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WakeSettingsRow(
              icon: Icons.verified_user_rounded,
              title: 'Require challenge for new alarms',
              subtitle: 'New alarms start with the wake challenge enabled',
              trailing: Switch(
                value: settings.defaultQrRequired,
                onChanged: (val) => context.read<SettingsBloc>().add(
                  ToggleDefaultQrRequiredEvent(val),
                ),
              ),
            ),
            _footnote(
              'Choose the QR or object-verification method — and the object to '
              'photograph — per alarm in the alarm editor. Challenges use '
              'on-device AI verification, with printed backup codes as a '
              'fallback.',
              icon: Icons.auto_awesome,
            ),
          ],
        ),
      ),
    );
  }

  // ---- Notifications ------------------------------------------------------

  Widget _buildNotificationsSection(SettingsState settings) {
    return WakeSection(
      title: 'Notifications',
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WakeSettingsRow(
              icon: Icons.notifications_active_rounded,
              title: 'Backup notifications',
              subtitle:
                  'Phone alarms mirror the clock in case it is unreachable',
              trailing: Switch(
                value: settings.backupNotificationsEnabled,
                onChanged: (val) => context.read<SettingsBloc>().add(
                  ToggleBackupNotificationsEvent(val),
                ),
              ),
            ),
            _footnote('Changes apply from the next alarm update.'),
          ],
        ),
      ),
    );
  }

  // ---- Data ---------------------------------------------------------------

  Widget _buildDataSection() {
    return WakeSection(
      title: 'Data',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shadows: wakeCardShadow(context),
        child: WakeSettingsRow(
          icon: Icons.history_rounded,
          title: 'Dismissal History',
          subtitle: 'When alarms fired and how they were dismissed',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const DismissalHistoryScreen()),
          ),
        ),
      ),
    );
  }

  // ---- General ------------------------------------------------------------

  Widget _buildGeneralSection() {
    return WakeSection(
      title: 'General',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            WakeSettingsRow(
              icon: Icons.info_rounded,
              title: 'About WakeGuard',
              subtitle: 'Version 1.0',
              onTap: _showAboutDialog,
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.privacy_tip_rounded,
              title: 'Privacy',
              subtitle: 'Camera verification and Bluetooth stay on this device',
              onTap: _showPrivacyDialog,
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.description_rounded,
              title: 'Licenses',
              subtitle: 'Open source software used by WakeGuard',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'WakeGuard',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WakeLogoMark(size: 92),
              const SizedBox(height: 18),
              Text(
                'WakeGuard',
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Version 1.0',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'WakeGuard pairs with a Bluetooth alarm clock and requires a '
                'personalized object wake challenge before protected alarms '
                'can be dismissed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Done'),
            ),
          ],
        );
      },
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Privacy'),
        content: const Text(
          'Wake-challenge photos are analyzed on this phone and never leave '
          'it. Bluetooth communication happens directly between your phone '
          'and the clock — WakeGuard has no servers and no accounts.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ---- Advanced -----------------------------------------------------------

  Widget _buildAdvancedSection() {
    return WakeSection(
      title: 'Advanced',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            if (widget.onExitDeveloperMode != null) ...[
              WakeSettingsRow(
                icon: Icons.link_off_rounded,
                title: 'Disconnect Simulated Clock',
                subtitle: 'Exit developer mode and pair your real clock',
                onTap: _confirmExitDeveloperMode,
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
            ] else if (widget.onUnpairDevice != null) ...[
              WakeSettingsRow(
                icon: Icons.bluetooth_disabled_rounded,
                title: 'Unpair Device',
                subtitle: 'Forget this clock and set up a new one',
                onTap: _confirmUnpair,
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
            ] else if (widget.onConnectClock != null) ...[
              WakeSettingsRow(
                icon: Icons.bluetooth_searching_rounded,
                title: 'Connect a Clock',
                subtitle: 'Pair your WakeGuard clock to sync alarms',
                onTap: widget.onConnectClock,
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
            ],
            WakeSettingsRow(
              icon: Icons.replay_rounded,
              title: 'Replay Onboarding',
              subtitle: 'Show the WakeGuard introduction again',
              onTap: _replayOnboarding,
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.delete_forever_rounded,
              title: 'Reset Local Data',
              subtitle: 'Clear alarms, timers, and history on this phone',
              destructive: true,
              onTap: _confirmResetLocalData,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmExitDeveloperMode() async {
    final onExit = widget.onExitDeveloperMode;
    if (onExit == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect simulated clock?'),
        content: const Text(
          'This leaves the demo clock and returns to pairing so you can '
          'connect your real WakeGuard clock. Your alarms, timers, and '
          'settings stay on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Disconnect',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    // Swaps the whole BLE backend subtree and drops back to the pairing screen,
    // so there is nothing left to do on this (now-unmounted) screen afterward.
    if (confirmed == true) onExit();
  }

  Future<void> _confirmUnpair() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Unpair this clock?'),
        content: const Text(
          'WakeGuard will disconnect and forget this clock, then restart setup '
          'so you can pair a clock again. Your alarms, timers, and settings stay '
          'on this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Unpair',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    final onUnpair = widget.onUnpairDevice;
    if (confirmed != true || onUnpair == null || !mounted) return;

    // Drop the live link and stop auto-reconnect, then hand off to the app-level
    // callback, which forgets the clock and flips the declarative `home:` route
    // back to onboarding. Routing the transition through that shared callback —
    // rather than mutating prefs and pushing a route from here — keeps the
    // widget tree and the persisted prefs from disagreeing about whether a
    // clock is paired (which could otherwise resurrect the "forgotten" clock on
    // the next app-level rebuild). OnboardingScreen finishes by pushing
    // SetupScreen, which pairs the next clock.
    context.read<BleConnectionBloc>().add(ForgetDeviceEvent());
    onUnpair();
  }

  Future<void> _replayOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hasSeenOnboarding', false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Onboarding will play on next launch.')),
    );
  }

  Future<void> _confirmResetLocalData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset local data?'),
        content: const Text(
          'This removes alarms, timers, and dismissal history from this '
          'phone. Deleted alarms are removed from the clock through the '
          'normal sync; the hardware is otherwise untouched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Reset',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // Delete every alarm through the normal delete event so device-sync
    // semantics (immediate removal when connected, pending delete otherwise)
    // are preserved.
    final bleState = context.read<BleConnectionBloc>().state;
    final device = bleState is BleConnected ? bleState.device : null;
    final alarmBloc = context.read<AlarmBloc>();
    for (final alarm in List.of(alarmBloc.state.alarms)) {
      alarmBloc.add(DeleteAlarmEvent(alarm.id, device));
    }

    final timerCubit = context.read<CountdownTimerCubit>();
    for (final timer in List.of(timerCubit.state)) {
      timerCubit.removeTimer(timer.id);
    }

    context.read<DismissalHistoryCubit>().clear();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Local alarms, timers, and history cleared.'),
      ),
    );
  }

  // ---- Shared -------------------------------------------------------------

  Widget _footnote(String text, {IconData icon = Icons.info_outline_rounded}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
