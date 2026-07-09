import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/glass.dart';
import '../../../core/theme/wake_widgets.dart';
import '../../../core/utils/alarm_time_utils.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';

/// The Display tab: customization for the physical WakeGuard clock's screen —
/// light/dark face theme, accent colour, and what the face shows (24-hour time,
/// seconds, the date line). Changes are pushed to the clock over BLE (0x06) the
/// instant they're toggled, and re-sent on every sync so the face stays in step.
class DisplayTab extends StatelessWidget {
  const DisplayTab({super.key});

  // Order MUST match the firmware ACCENTS[] table (0 amber .. 3 violet).
  static const List<({String name, Color color})> _accents = [
    (name: 'Amber', color: Color(0xFFFFA000)),
    (name: 'Blue', color: Color(0xFF3B82F6)),
    (name: 'Green', color: Color(0xFF2ECC71)),
    (name: 'Violet', color: Color(0xFF8B5CF6)),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        bottom: false,
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settings) {
            // Dispatch a display update carrying the current values, overriding
            // only the field that changed.
            void update({
              bool? themeLight,
              int? accentIndex,
              bool? showSeconds,
              bool? showDate,
              bool? showDayOfWeek,
              int? dateFormat,
            }) {
              context.read<SettingsBloc>().add(
                UpdateClockDisplayEvent(
                  themeLight: themeLight ?? settings.clockThemeLight,
                  accentIndex: accentIndex ?? settings.clockAccentIndex,
                  showSeconds: showSeconds ?? settings.clockShowSeconds,
                  showDate: showDate ?? settings.clockShowDate,
                  showDayOfWeek: showDayOfWeek ?? settings.clockShowDayOfWeek,
                  dateFormat: dateFormat ?? settings.clockDateFormat,
                ),
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 130),
              children: [
                Text(
                  'Display',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'Customize the clock’s screen',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                _connectionHint(context),
                const SizedBox(height: 24),
                _themeSection(context, settings, update),
                const SizedBox(height: 24),
                _accentSection(context, settings, update),
                const SizedBox(height: 24),
                _optionsSection(context, settings, update),
                const SizedBox(height: 24),
                _sleepSection(context, settings),
                const SizedBox(height: 24),
                _weatherSection(context, settings),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Small banner clarifying that these settings target the hardware, so their
  /// effect only shows once the clock is connected (they're saved regardless).
  Widget _connectionHint(BuildContext context) {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        final connected = bleState is BleConnected;
        final scheme = Theme.of(context).colorScheme;
        final color = connected ? AppColors.success : AppColors.warning;
        return GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shadows: wakeCardShadow(context),
          child: Row(
            children: [
              Icon(
                connected
                    ? Icons.check_circle_rounded
                    : Icons.bluetooth_disabled_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  connected
                      ? 'Changes apply to your clock right away.'
                      : 'Saved now — applied when the clock next connects.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _themeSection(
    BuildContext context,
    SettingsState settings,
    void Function({
      bool? themeLight,
      int? accentIndex,
      bool? showSeconds,
      bool? showDate,
      bool? showDayOfWeek,
      int? dateFormat,
    }) update,
  ) {
    return WakeSection(
      title: 'Theme',
      subtitle: 'The clock face colour scheme.',
      child: GlassCard(
        padding: const EdgeInsets.all(8),
        shadows: wakeCardShadow(context),
        child: Row(
          children: [
            _segment(
              context,
              label: 'Dark',
              icon: Icons.dark_mode_rounded,
              selected: !settings.clockThemeLight,
              onTap: () => update(themeLight: false),
            ),
            const SizedBox(width: 8),
            _segment(
              context,
              label: 'Light',
              icon: Icons.light_mode_rounded,
              selected: settings.clockThemeLight,
              onTap: () => update(themeLight: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _segment(
    BuildContext context, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _accentSection(
    BuildContext context,
    SettingsState settings,
    void Function({
      bool? themeLight,
      int? accentIndex,
      bool? showSeconds,
      bool? showDate,
      bool? showDayOfWeek,
      int? dateFormat,
    }) update,
  ) {
    return WakeSection(
      title: 'Accent',
      subtitle: 'Highlight colour for the title, status line, and link dot.',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        shadows: wakeCardShadow(context),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (int i = 0; i < _accents.length; i++)
              _swatch(
                context,
                color: _accents[i].color,
                label: _accents[i].name,
                selected: settings.clockAccentIndex == i,
                onTap: () => update(accentIndex: i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _swatch(
    BuildContext context, {
    required Color color,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      selected: selected,
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.onSurface : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 22)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _optionsSection(
    BuildContext context,
    SettingsState settings,
    void Function({
      bool? themeLight,
      int? accentIndex,
      bool? showSeconds,
      bool? showDate,
      bool? showDayOfWeek,
      int? dateFormat,
    }) update,
  ) {
    return WakeSection(
      title: 'Clock Face',
      subtitle: 'What the clock shows.',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            WakeSettingsRow(
              icon: Icons.schedule_rounded,
              title: '24-Hour Time',
              subtitle: 'Show 14:30 instead of 2:30 PM (app-wide)',
              trailing: Switch(
                value: settings.is24HourTime,
                onChanged: (v) =>
                    context.read<SettingsBloc>().add(Toggle24HourTimeEvent(v)),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.timer_outlined,
              title: 'Show Seconds',
              subtitle: 'Add seconds to the big time',
              trailing: Switch(
                value: settings.clockShowSeconds,
                onChanged: (v) => update(showSeconds: v),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.today_rounded,
              title: 'Show Day of Week',
              subtitle: 'e.g. “Wednesday” under the time',
              trailing: Switch(
                value: settings.clockShowDayOfWeek,
                onChanged: (v) => update(showDayOfWeek: v),
              ),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
            WakeSettingsRow(
              icon: Icons.calendar_today_rounded,
              title: 'Show Date',
              subtitle: 'Display the calendar date under the time',
              trailing: Switch(
                value: settings.clockShowDate,
                onChanged: (v) => update(showDate: v),
              ),
            ),
            if (settings.clockShowDate) ...[
              Divider(height: 1, color: Theme.of(context).dividerColor),
              _dateFormatPicker(context, settings, update),
            ],
          ],
        ),
      ),
    );
  }

  // Example labels MUST line up with the firmware's dispDateFmt / the app's
  // clockDateFormat index (0..3). Kept as short samples so the choice is obvious.
  static const List<String> _dateFormatSamples = [
    'Jul 8', // 0  MMM D
    '8 Jul', // 1  D MMM
    '07/08/26', // 2  MM/DD/YY
    '2026-07-08', // 3  YYYY-MM-DD
  ];

  Widget _dateFormatPicker(
    BuildContext context,
    SettingsState settings,
    void Function({
      bool? themeLight,
      int? accentIndex,
      bool? showSeconds,
      bool? showDate,
      bool? showDayOfWeek,
      int? dateFormat,
    }) update,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Date format',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (int i = 0; i < _dateFormatSamples.length; i++)
                _formatChip(
                  context,
                  label: _dateFormatSamples[i],
                  selected: settings.clockDateFormat == i,
                  onTap: () => update(dateFormat: i),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _formatChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: 1.4,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// Scheduled display sleep: blank the clock's screen overnight. Dispatches
  /// [UpdateClockSleepEvent] (command 0x0D). The backlight is hardwired-on, so the
  /// face is hidden but a faint glow remains — [_sleepHint] says so honestly.
  Widget _sleepSection(BuildContext context, SettingsState settings) {
    final bloc = context.read<SettingsBloc>();
    final enabled = settings.clockSleepEnabled;

    void dispatch({bool? on, int? startMinutes, int? endMinutes}) {
      bloc.add(
        UpdateClockSleepEvent(
          enabled: on ?? settings.clockSleepEnabled,
          startMinutes: startMinutes ?? settings.clockSleepStartMinutes,
          endMinutes: endMinutes ?? settings.clockSleepEndMinutes,
        ),
      );
    }

    return WakeSection(
      title: 'Sleep',
      subtitle: 'Blank the clock’s screen overnight so it doesn’t light the room.',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            WakeSettingsRow(
              icon: Icons.bedtime_rounded,
              title: 'Sleep Schedule',
              subtitle: 'Turn the screen dark during set hours',
              trailing: Switch(
                value: enabled,
                onChanged: (v) => dispatch(on: v),
              ),
            ),
            if (enabled) ...[
              Divider(height: 1, color: Theme.of(context).dividerColor),
              _sleepTimeRow(
                context,
                settings,
                label: 'Sleep at',
                icon: Icons.nightlight_round,
                minutes: settings.clockSleepStartMinutes,
                onPicked: (m) => dispatch(startMinutes: m),
              ),
              Divider(height: 1, color: Theme.of(context).dividerColor),
              _sleepTimeRow(
                context,
                settings,
                label: 'Wake at',
                icon: Icons.wb_twilight_rounded,
                minutes: settings.clockSleepEndMinutes,
                onPicked: (m) => dispatch(endMinutes: m),
              ),
              _sleepHint(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sleepTimeRow(
    BuildContext context,
    SettingsState settings, {
    required String label,
    required IconData icon,
    required int minutes,
    required ValueChanged<int> onPicked,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final display = AlarmTimeUtils.formatTime(
      minutes ~/ 60,
      minutes % 60,
      is24Hour: settings.is24HourTime,
    );
    return WakeSettingsRow(
      icon: icon,
      title: label,
      subtitle: 'Tap to change',
      trailing: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
          );
          if (picked != null) onPicked(picked.hour * 60 + picked.minute);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: scheme.primary.withValues(alpha: 0.16),
            border: Border.all(color: scheme.primary, width: 1.4),
          ),
          child: Text(
            display,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _sleepHint(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'The clock face is hidden during these hours. Its backlight is '
              'always-on hardware, so a faint glow remains. An alarm still lights '
              'the screen and rings.',
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

  Widget _weatherSection(BuildContext context, SettingsState settings) {
    final bloc = context.read<SettingsBloc>();
    return WakeSection(
      title: 'Weather',
      subtitle:
          'Your phone fetches local conditions and shows them top-right on the clock.',
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            WakeSettingsRow(
              icon: Icons.wb_sunny_rounded,
              title: 'Show Weather',
              subtitle: 'Temperature + a condition icon on the clock face',
              trailing: Switch(
                value: settings.showWeather,
                onChanged: (v) => bloc.add(ToggleShowWeatherEvent(v)),
              ),
            ),
            if (settings.showWeather) ...[
              Divider(height: 1, color: Theme.of(context).dividerColor),
              WakeSettingsRow(
                icon: Icons.thermostat_rounded,
                title: 'Units',
                subtitle: 'Temperature scale shown on the clock',
                trailing: _unitToggle(context, settings),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _unitToggle(BuildContext context, SettingsState settings) {
    final scheme = Theme.of(context).colorScheme;
    final bloc = context.read<SettingsBloc>();
    Widget pill(String label, bool selected, VoidCallback onTap) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? scheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 1.4,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill('°C', !settings.weatherFahrenheit,
            () => bloc.add(const ToggleWeatherUnitEvent(false))),
        const SizedBox(width: 6),
        pill('°F', settings.weatherFahrenheit,
            () => bloc.add(const ToggleWeatherUnitEvent(true))),
      ],
    );
  }
}
