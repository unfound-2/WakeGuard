import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/core/platform/android_alarm_channel.dart';
import 'package:smart_ble_alarm/core/theme/app_background.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/bloc/alarm_bloc.dart';
import 'package:smart_ble_alarm/features/account/presentation/cubit/account_cubit.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_event.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_state.dart';
import 'package:smart_ble_alarm/features/history/presentation/cubit/dismissal_history_cubit.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:smart_ble_alarm/features/timers/presentation/cubit/countdown_timer_cubit.dart';
import 'package:smart_ble_alarm/features/account/presentation/screens/account_screen.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/tabs/clock_tab.dart';
import 'package:smart_ble_alarm/features/history/presentation/screens/dismissal_history_screen.dart';

/// App preferences in the native WakeGuard SettingsView layout: merged profile
/// and account, a compact status summary, and a few grouped rows that open
/// detailed settings pages. The clock's screen customization lives on the
/// Display tab.
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

  /// When provided (from `main.dart`), the Phone Alarm section shows a "Use this
  /// phone as a dedicated clock (Beta)" action that turns this device into a
  /// standby bedside clock. Null hides the row.
  final VoidCallback? onSetupDedicatedClock;

  /// Replays onboarding immediately without requiring an app restart.
  final Future<void> Function()? onReplayOnboarding;

  const SettingsScreen({
    super.key,
    this.isTab = false,
    this.onExitDeveloperMode,
    this.onUnpairDevice,
    this.onConnectClock,
    this.onSetupDedicatedClock,
    this.onReplayOnboarding,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const List<String> _themeOptions = ['System', 'Light', 'Dark'];
  final TextEditingController _settingsSearchController =
      TextEditingController();
  String _settingsQuery = '';

  @override
  void dispose() {
    _settingsSearchController.dispose();
    super.dispose();
  }

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
                _buildSettingsSearchField(),
                const SizedBox(height: 16),
                if (_settingsQuery.trim().isNotEmpty) ...[
                  _buildSearchResults(settings),
                  const SizedBox(height: 22),
                ] else ...[
                  _buildProfileAccountCard(),
                  const SizedBox(height: 16),
                  _buildStatusSummaryCard(settings),
                  const SizedBox(height: 22),
                  _buildMainSettingsGroups(settings),
                  const SizedBox(height: 22),
                  _buildAdvancedSection(),
                ],
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

  Widget _buildSettingsSearchField() {
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _settingsSearchController,
      textInputAction: TextInputAction.search,
      onChanged: (value) => setState(() => _settingsQuery = value),
      decoration: InputDecoration(
        hintText: 'Search settings',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _settingsQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _settingsSearchController.clear();
                  setState(() => _settingsQuery = '');
                },
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: GlassTheme.of(context).stroke),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: GlassTheme.of(context).stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildSearchResults(SettingsState settings) {
    final query = _settingsQuery.trim().toLowerCase();
    final rows = <Widget>[
      if (_matches(query, ['account', 'profile', 'name', 'photo', 'sign in']))
        WakeSettingsRow(
          icon: Icons.person_rounded,
          title: 'Profile & Account',
          subtitle: 'Name, photo, sign-in, and cloud sync',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountScreen()),
          ),
        ),
      if (_matches(query, ['restore', 'cloud', 'backup', 'sync']))
        WakeSettingsRow(
          icon: Icons.cloud_download_rounded,
          title: 'Restore Alarm Backups',
          subtitle: 'Merge saved cloud alarms onto this phone',
          onTap: _restoreCloudBackups,
        ),
      if (_matches(query, ['clock', 'bluetooth', 'pair', 'sync']))
        WakeSettingsRow(
          icon: Icons.watch_rounded,
          title: 'Clock & Sync',
          subtitle: 'Connection, device sync, and time behavior',
          onTap: () => _openSettingsDetail(
            title: 'Clock & Sync',
            subtitle: 'Connection, device sync, and time behavior.',
            builder: (context, settings) => Column(
              children: [
                _buildClockDeviceSection(),
                const SizedBox(height: 22),
                _buildTimeSection(settings),
              ],
            ),
          ),
        ),
      if (_matches(query, ['challenge', 'dismissal', 'qr', 'photo', 'object']))
        WakeSettingsRow(
          icon: Icons.verified_user_rounded,
          title: 'Wake Challenge',
          subtitle: settings.defaultQrRequired
              ? 'Required by default'
              : 'Optional by default',
          onTap: () => _openSettingsDetail(
            title: 'Wake Challenge',
            subtitle: 'Default challenge behavior for new alarms.',
            builder: (context, settings) => _buildChallengeSection(settings),
          ),
        ),
      if (_matches(query, ['notification', 'backup', 'phone', 'reminder']))
        WakeSettingsRow(
          icon: Icons.notifications_active_rounded,
          title: 'Backup & Phone Alarm',
          subtitle: 'Phone fallback, reminder, and dedicated clock',
          onTap: () => _openSettingsDetail(
            title: 'Backup & Phone Alarm',
            subtitle: 'Phone-side fallback options and limitations.',
            builder: (context, settings) => Column(
              children: [
                _buildNotificationsSection(settings),
                const SizedBox(height: 22),
                _buildPhoneAlarmSection(settings),
              ],
            ),
          ),
        ),
      if (_matches(query, ['appearance', 'theme', 'accent', 'background']))
        WakeSettingsRow(
          icon: Icons.palette_rounded,
          title: 'Appearance',
          subtitle:
              '${settings.themeString} · ${AppColors.canonicalAccentName(settings.accentColorString)}',
          onTap: () => _openSettingsDetail(
            title: 'Appearance',
            subtitle: 'Theme, accent, background, and motion.',
            builder: (context, settings) => _buildAppearanceSection(settings),
          ),
        ),
      if (_matches(query, ['privacy', 'data', 'history', 'license']))
        WakeSettingsRow(
          icon: Icons.history_rounded,
          title: 'Privacy & Data',
          subtitle: 'History, restore, privacy, licenses, and app info',
          onTap: () => _openPrivacyDataDetail(),
        ),
      if (_matches(query, ['onboarding', 'intro', 'tutorial', 'replay']))
        WakeSettingsRow(
          icon: Icons.replay_rounded,
          title: 'Replay Onboarding',
          subtitle: 'Show the WakeGuard introduction now',
          onTap: _replayOnboarding,
        ),
      if (_matches(query, ['reset', 'delete', 'clear']))
        WakeSettingsRow(
          icon: Icons.delete_forever_rounded,
          title: 'Reset Local Data',
          subtitle: 'Clear alarms, timers, and history on this phone',
          destructive: true,
          onTap: _confirmResetLocalData,
        ),
    ];

    if (rows.isEmpty) {
      return _emptySettingsSearch();
    }

    return WakeSection(
      title: 'Search Results',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        borderRadius: 24,
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(height: 1, color: Theme.of(context).dividerColor),
              rows[i],
            ],
          ],
        ),
      ),
    );
  }

  bool _matches(String query, List<String> terms) {
    return terms.any((term) => term.contains(query) || query.contains(term));
  }

  Widget _emptySettingsSearch() {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(18),
      borderRadius: 24,
      shadows: wakeCardShadow(context),
      child: Row(
        children: [
          Icon(Icons.search_off_rounded, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'No settings found for "$_settingsQuery".',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileAccountCard() {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<AccountCubit, AccountState>(
      builder: (context, account) {
        final name = account.displayName?.trim().isNotEmpty == true
            ? account.displayName!.trim()
            : 'WakeGuard';
        final subtitle = account.isSignedIn
            ? account.email ?? 'Cloud sync connected'
            : account.firebaseReady
            ? 'Local mode · add an account when ready'
            : 'Local mode · Firebase setup pending';
        final pillColor = account.isSignedIn
            ? AppColors.success
            : account.firebaseReady
            ? scheme.primary
            : scheme.onSurfaceVariant;
        final pillLabel = account.isSignedIn
            ? 'Signed in'
            : account.firebaseReady
            ? 'Local'
            : 'Offline';
        return GlassCard(
          padding: const EdgeInsets.all(16),
          borderRadius: 26,
          shadows: wakeCardShadow(context),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AccountScreen()),
          ),
          child: Row(
            children: [
              _accountAvatar(account),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),
                    WakeStatusPill(
                      label: pillLabel,
                      icon: account.isSignedIn
                          ? Icons.cloud_done_rounded
                          : Icons.person_outline_rounded,
                      color: pillColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                account.isSignedIn ? 'Edit' : 'Account',
                style: TextStyle(
                  color: scheme.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _accountAvatar(AccountState account) {
    final url = account.photoUrl;
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(
        radius: 31,
        backgroundImage: NetworkImage(url),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      );
    }
    return const WakeLogoMark(size: 62);
  }

  Widget _buildStatusSummaryCard(SettingsState settings) {
    return BlocBuilder<AccountCubit, AccountState>(
      builder: (context, account) {
        return BlocBuilder<BleConnectionBloc, BleState>(
          builder: (context, bleState) {
            final connected = bleState is BleConnected;
            final busy = bleState is BleConnecting || bleState is BleScanning;
            return GlassCard(
              padding: const EdgeInsets.all(14),
              borderRadius: 24,
              shadows: wakeCardShadow(context),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth < 300
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 10) / 2;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: itemWidth,
                        child: _statusTile(
                          icon: connected
                              ? Icons.bluetooth_connected_rounded
                              : busy
                              ? Icons.bluetooth_searching_rounded
                              : Icons.bluetooth_disabled_rounded,
                          label: 'Clock',
                          value: connected
                              ? 'Connected'
                              : busy
                              ? 'Searching'
                              : 'Offline',
                          color: connected
                              ? AppColors.success
                              : busy
                              ? Theme.of(context).colorScheme.primary
                              : AppColors.warning,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _statusTile(
                          icon: account.isSignedIn
                              ? Icons.cloud_done_rounded
                              : Icons.person_outline_rounded,
                          label: 'Account',
                          value: account.isSignedIn ? 'Synced' : 'Local',
                          color: account.isSignedIn
                              ? AppColors.success
                              : Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _statusTile(
                          icon: Icons.notifications_active_rounded,
                          label: 'Backup',
                          value: settings.backupNotificationsEnabled
                              ? 'On'
                              : 'Off',
                          color: settings.backupNotificationsEnabled
                              ? AppColors.success
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      SizedBox(
                        width: itemWidth,
                        child: _statusTile(
                          icon: Icons.nights_stay_rounded,
                          label: 'Reminder',
                          value: settings.eveningReminderEnabled
                              ? '9:00 PM'
                              : 'Off',
                          color: settings.eveningReminderEnabled
                              ? AppColors.warning
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainSettingsGroups(SettingsState settings) {
    return Column(
      children: [
        _settingsGroup(
          title: 'Clock & Sync',
          children: [
            WakeSettingsRow(
              icon: Icons.watch_rounded,
              title: 'WakeGuard Clock',
              subtitle: _clockSummary(),
              onTap: () => _openSettingsDetail(
                title: 'Clock & Sync',
                subtitle: 'Connection, device sync, and time behavior.',
                builder: (context, settings) => Column(
                  children: [
                    _buildClockDeviceSection(),
                    const SizedBox(height: 22),
                    _buildTimeSection(settings),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _settingsGroup(
          title: 'Alarm Behavior',
          children: [
            WakeSettingsRow(
              icon: Icons.verified_user_rounded,
              title: 'Wake Challenge',
              subtitle: settings.defaultQrRequired
                  ? 'Required by default'
                  : 'Optional by default',
              onTap: () => _openSettingsDetail(
                title: 'Wake Challenge',
                subtitle: 'Default challenge behavior for new alarms.',
                builder: (context, settings) =>
                    _buildChallengeSection(settings),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.notifications_active_rounded,
              title: 'Backup & Phone Alarm',
              subtitle:
                  '${settings.backupNotificationsEnabled ? 'Backup on' : 'Backup off'} · '
                  '${settings.eveningReminderEnabled ? 'reminder on' : 'reminder off'}',
              onTap: () => _openSettingsDetail(
                title: 'Backup & Phone Alarm',
                subtitle: 'Phone-side fallback options and limitations.',
                builder: (context, settings) => Column(
                  children: [
                    _buildNotificationsSection(settings),
                    const SizedBox(height: 22),
                    _buildPhoneAlarmSection(settings),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _settingsGroup(
          title: 'App',
          children: [
            WakeSettingsRow(
              icon: Icons.palette_rounded,
              title: 'Appearance',
              subtitle:
                  '${settings.themeString} · ${AppColors.canonicalAccentName(settings.accentColorString)}',
              onTap: () => _openSettingsDetail(
                title: 'Appearance',
                subtitle: 'Theme, accent, background, and motion.',
                builder: (context, settings) =>
                    _buildAppearanceSection(settings),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.history_rounded,
              title: 'Privacy & Data',
              subtitle: 'History, restore, privacy, licenses, and app info',
              onTap: _openPrivacyDataDetail,
            ),
          ],
        ),
      ],
    );
  }

  String _clockSummary() {
    final state = context.read<BleConnectionBloc>().state;
    if (state is BleConnected) return 'Connected and ready to sync';
    if (state is BleConnecting || state is BleScanning) return 'Searching now';
    return 'Bluetooth connection and backup code';
  }

  Widget _settingsGroup({
    required String title,
    required List<Widget> children,
  }) {
    return WakeSection(
      title: title,
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
        borderRadius: 24,
        shadows: wakeCardShadow(context),
        child: Column(children: children),
      ),
    );
  }

  void _openSettingsDetail({
    required String title,
    required String subtitle,
    required Widget Function(BuildContext context, SettingsState settings)
    builder,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SettingsDetailScreen(
          title: title,
          subtitle: subtitle,
          builder: builder,
        ),
      ),
    );
  }

  void _openPrivacyDataDetail() {
    _openSettingsDetail(
      title: 'Privacy & Data',
      subtitle: 'Cloud restore, local history, app information, and privacy.',
      builder: (context, settings) => Column(
        children: [
          _buildDataSection(),
          const SizedBox(height: 22),
          _buildGeneralSection(),
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
                    AppColors.canonicalAccentName(settings.accentColorString) ==
                        name,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(height: 17, color: Theme.of(context).dividerColor),
            Text(
              'Background',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            _backgroundPicker(settings),
            Divider(height: 17, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.animation_rounded,
              title: 'Animated controls',
              subtitle:
                  'Animate the day picker and use haptics when editing '
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

  /// A row of live preview tiles for the app's ambient background style. Tapping
  /// one switches every screen's backdrop immediately (via the appBackgroundStyle
  /// notifier that GlassBackground listens to).
  Widget _backgroundPicker(SettingsState settings) {
    final glass = GlassTheme.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final styles = AppBackgroundStyle.values;
    return Row(
      children: [
        for (int i = 0; i < styles.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i == styles.length - 1 ? 0 : 10),
              child: _backgroundTile(
                style: styles[i],
                selected: settings.appBackground == styles[i],
                baseGradient: glass.backgroundGradient,
                accent: accent,
                animate: !reduceMotion,
              ),
            ),
          ),
      ],
    );
  }

  Widget _backgroundTile({
    required AppBackgroundStyle style,
    required bool selected,
    required List<Color> baseGradient,
    required Color accent,
    required bool animate,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: '${style.label} background',
      child: GestureDetector(
        onTap: () =>
            context.read<SettingsBloc>().add(UpdateAppBackgroundEvent(style)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 0.8,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? accent : GlassTheme.of(context).stroke,
                  width: selected ? 2 : 1,
                ),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: AppBackgroundPreview(
                      style: style,
                      baseGradient: baseGradient,
                      accent: accent,
                      animate: animate,
                    ),
                  ),
                  if (selected)
                    Positioned(
                      top: 5,
                      right: 5,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            style.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : scheme.onSurfaceVariant,
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
      child: Semantics(
        button: true,
        selected: selected,
        label: '$name accent color',
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
                BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10),
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
            Divider(height: 20, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.nights_stay_rounded,
              title: 'Evening readiness reminder',
              subtitle: 'A 9 PM check-in to set tomorrow\'s alarm',
              trailing: Switch(
                value: settings.eveningReminderEnabled,
                onChanged: (val) => context.read<SettingsBloc>().add(
                  ToggleEveningReminderEvent(val),
                ),
              ),
            ),
            // Android-only; renders nothing on iOS. Lets the alarm pop over the
            // lock screen and other apps by granting SYSTEM_ALERT_WINDOW.
            const _OverlayPermissionRow(),
            _footnote(
              'Backup notifications mirror active alarms. The evening reminder '
              'is a gentle daily prompt and does not ring like an alarm.',
            ),
          ],
        ),
      ),
    );
  }

  // ---- Ring on this phone -------------------------------------------------

  /// Phone-side ringing: the "Ring on this phone" foreground engine (this
  /// primary phone rings itself when an alarm's time arrives, running the wake
  /// challenge to dismiss) plus the Dedicated Clock mode that turns a spare
  /// phone into a standby bedside clock face.
  Widget _buildPhoneAlarmSection(SettingsState settings) {
    final divider = Divider(height: 20, color: Theme.of(context).dividerColor);
    return WakeSection(
      title: 'Ring on this phone (Beta)',
      subtitle: 'Let this phone ring alarms itself, without the clock.',
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            WakeSettingsRow(
              icon: Icons.phone_iphone_rounded,
              title: 'Ring on this phone',
              subtitle:
                  'Beta · rings and runs the wake challenge while the app is open',
              trailing: Switch(
                value: settings.phoneAlarmEnabled,
                onChanged: (val) => context.read<SettingsBloc>().add(
                  TogglePhoneAlarmEvent(val),
                ),
              ),
            ),
            if (widget.onSetupDedicatedClock != null) ...[
              divider,
              WakeSettingsRow(
                icon: Icons.phonelink_ring_rounded,
                title: 'Use this phone as a dedicated clock',
                subtitle:
                    'Beta · make a spare device a standby bedside clock face',
                onTap: widget.onSetupDedicatedClock,
              ),
            ],
            _footnote(
              'Ringing here is best-effort: it works while WakeGuard is open, '
              'and the "Backup notifications" above cover it when the app is '
              'closed. For a guaranteed, tamper-proof alarm, use the WakeGuard '
              'hardware clock.',
              icon: Icons.info_outline_rounded,
            ),
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
        child: Column(
          children: [
            WakeSettingsRow(
              icon: Icons.cloud_download_rounded,
              title: 'Restore alarm backups',
              subtitle: 'Merge saved cloud alarms onto this phone',
              onTap: _restoreCloudBackups,
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.history_rounded,
              title: 'Dismissal History',
              subtitle: 'When alarms fired and how they were dismissed',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const DismissalHistoryScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreCloudBackups() async {
    final account = context.read<AccountCubit>().state;
    final messenger = ScaffoldMessenger.of(context);
    if (!account.isSignedIn) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('Sign in before restoring cloud alarm backups.'),
          ),
        );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore alarm backups?'),
        content: const Text(
          'WakeGuard will merge alarms saved in your cloud backup onto this '
          'phone. Existing alarms with the same slot are updated.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Restore',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final completer = Completer<int>();
    context.read<AlarmBloc>().add(
      RestoreAlarmBackupsEvent(completer: completer),
    );
    try {
      final count = await completer.future;
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              count == 0
                  ? 'No cloud alarm backups were found.'
                  : 'Restored $count cloud alarm backup${count == 1 ? '' : 's'}.',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: const Text('Cloud restore failed. Try again in a moment.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    }
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
              title: 'Privacy Policy',
              subtitle: 'Accounts, backups, diagnostics, and device data',
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
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              Text(
                'WakeGuard pairs with a Bluetooth alarm clock and requires a '
                'personalized object wake challenge before protected alarms '
                'can be dismissed. WakeGuard is a routine-support tool, not a '
                'medical device, and it does not diagnose, treat, or prevent '
                'any medical condition.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Credits',
                style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Aaron Hua, Mekyle Alam, Victor Kong, & Navin John',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
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
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'Wake-challenge camera images are processed on this phone for QR '
            'and object checks. They are not saved by WakeGuard.\n\n'
            'Bluetooth communication happens directly between your phone and '
            'your WakeGuard clock.\n\n'
            'If you enable weather on the clock, WakeGuard sends your phone\'s '
            'IP address to ipapi.co to estimate your approximate location, then '
            'requests the local forecast from Open-Meteo. No precise GPS '
            'location is used, and weather can be turned off in the Display '
            'settings.\n\n'
            'If you sign in, Firebase stores your email, name, optional '
            'profile photo, and cloud alarm backups so WakeGuard can restore '
            'your setup. Firebase Analytics records onboarding and sync '
            'events, and Firebase Crashlytics records crash diagnostics. '
            'WakeGuard does not sell personal data or track you across apps.\n\n'
            'Delete Account removes your WakeGuard cloud profile and alarm '
            'backups. Local alarms on this phone stay until you reset local '
            'data or delete the app.\n\n'
            'WakeGuard is not a medical device and should not replace medical '
            'advice. For narcolepsy, sleep disorders, medication routines, or '
            'other health decisions, talk with a qualified clinician.',
          ),
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
    final onReplay = widget.onReplayOnboarding;
    if (onReplay != null) {
      await onReplay();
      return;
    }
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

class _SettingsDetailScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget Function(BuildContext context, SettingsState settings) builder;

  const _SettingsDetailScreen({
    required this.title,
    required this.subtitle,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(title)),
      body: GlassBackground(
        child: SafeArea(
          child: BlocBuilder<SettingsBloc, SettingsState>(
            builder: (context, settings) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 22),
                  builder(context, settings),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Android-only row for the "Display over other apps" (SYSTEM_ALERT_WINDOW)
/// permission. Granting it lets the full-screen alarm reliably appear over the
/// lock screen and whatever else is on-screen — several OEM builds suppress
/// full-screen-intent alarms unless overlay is allowed.
///
/// The permission can only be granted from system Settings (the app can't set
/// it directly), so the switch deep-links there and reflects the live grant
/// state, re-reading it whenever the app returns to the foreground. On iOS —
/// and any non-Android platform — it renders nothing.
class _OverlayPermissionRow extends StatefulWidget {
  const _OverlayPermissionRow();

  @override
  State<_OverlayPermissionRow> createState() => _OverlayPermissionRowState();
}

class _OverlayPermissionRowState extends State<_OverlayPermissionRow>
    with WidgetsBindingObserver {
  bool _granted = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addObserver(this);
      _refresh();
    }
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-read once the user comes back from the system settings screen.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final granted = await AndroidAlarmChannel.canDrawOverlays();
    if (!mounted) return;
    setState(() {
      _granted = granted;
      _checked = true;
    });
  }

  Future<void> _openSettings() async {
    // The grant happens in system Settings; the resume-lifecycle refresh picks
    // up the new state when the user returns.
    await AndroidAlarmChannel.requestOverlayPermission();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 20, color: Theme.of(context).dividerColor),
        WakeSettingsRow(
          icon: Icons.layers_rounded,
          title: 'Display over other apps',
          subtitle: !_checked
              ? 'Checking permission…'
              : _granted
              ? 'Allowed — the alarm can appear over the lock screen'
              : 'Tap to allow the alarm over the lock screen and other apps',
          onTap: _openSettings,
          trailing: Switch(
            value: _granted,
            // The OS owns this permission, so both directions just deep-link to
            // the system screen; the switch reflects the real state on resume.
            onChanged: (_) => _openSettings(),
          ),
        ),
      ],
    );
  }
}
