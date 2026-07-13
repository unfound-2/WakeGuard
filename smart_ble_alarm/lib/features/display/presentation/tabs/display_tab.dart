import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_ble_alarm/core/theme/app_colors.dart';
import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/core/utils/alarm_time_utils.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_bloc.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_event.dart';
import 'package:smart_ble_alarm/features/bluetooth/presentation/bloc/ble_state.dart';
import 'package:smart_ble_alarm/features/settings/presentation/bloc/settings_bloc.dart';

typedef _DisplayUpdate =
    void Function({
      bool? themeLight,
      int? accentIndex,
      bool? showSeconds,
      bool? showDate,
      bool? showDayOfWeek,
      int? dateFormat,
    });

/// The Display tab: customization for the physical WakeGuard clock's screen.
/// Changes are saved locally, pushed live over BLE when the clock is connected,
/// and re-sent during full sync.
class DisplayTab extends StatelessWidget {
  const DisplayTab({super.key});

  // Order MUST match the firmware ACCENTS[] table (0 amber .. 3 violet).
  static const List<({String name, Color color})> _accents = [
    (name: 'Amber', color: Color(0xFFFFA000)),
    (name: 'Blue', color: Color(0xFF3B82F6)),
    (name: 'Green', color: Color(0xFF2ECC71)),
    (name: 'Violet', color: Color(0xFF8B5CF6)),
  ];

  static const List<_DisplayPreset> _presets = [
    _DisplayPreset(
      name: 'Minimal',
      description: 'Big time only',
      icon: Icons.view_agenda_rounded,
      themeLight: false,
      accentIndex: 0,
      showSeconds: false,
      showDate: false,
      showDayOfWeek: false,
      dateFormat: 0,
      showWeather: false,
      sleepEnabled: false,
    ),
    _DisplayPreset(
      name: 'Nightstand',
      description: 'Quiet overnight',
      icon: Icons.bedtime_rounded,
      themeLight: false,
      accentIndex: 0,
      showSeconds: false,
      showDate: true,
      showDayOfWeek: true,
      dateFormat: 0,
      showWeather: true,
      sleepEnabled: true,
      sleepStartMinutes: 22 * 60,
      sleepEndMinutes: 7 * 60,
    ),
    _DisplayPreset(
      name: 'Weather',
      description: 'Forecast glance',
      icon: Icons.wb_sunny_rounded,
      themeLight: false,
      accentIndex: 1,
      showSeconds: false,
      showDate: true,
      showDayOfWeek: true,
      dateFormat: 0,
      showWeather: true,
      sleepEnabled: false,
    ),
    _DisplayPreset(
      name: 'High Contrast',
      description: 'Bright & legible',
      icon: Icons.contrast_rounded,
      themeLight: true,
      accentIndex: 1,
      showSeconds: true,
      showDate: true,
      showDayOfWeek: false,
      dateFormat: 0,
      showWeather: false,
      sleepEnabled: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      child: SafeArea(
        bottom: false,
        child: BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settings) {
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
                  'Shape the clock face before it reaches your nightstand.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 18),
                _livePreviewSection(context, settings),
                const SizedBox(height: 16),
                _connectionStateCard(context),
                const SizedBox(height: 24),
                _presetSection(context, settings),
                const SizedBox(height: 24),
                _appearanceSection(context, settings, update),
                const SizedBox(height: 24),
                _faceSection(context, settings, update),
                const SizedBox(height: 24),
                _nightModeSection(context, settings),
                const SizedBox(height: 24),
                _weatherSection(context, settings),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _livePreviewSection(BuildContext context, SettingsState settings) {
    return WakeSection(
      title: 'Live Preview',
      subtitle: 'A close read of what the WakeGuard display will show.',
      child: BlocBuilder<BleConnectionBloc, BleState>(
        builder: (context, bleState) {
          return GlassCard(
            padding: const EdgeInsets.all(16),
            borderRadius: 30,
            shadows: wakeCardShadow(context),
            child: _ClockFacePreview(
              settings: settings,
              accent: _accentFor(settings),
              connected: bleState is BleConnected,
            ),
          );
        },
      ),
    );
  }

  Widget _connectionStateCard(BuildContext context) {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, bleState) {
        final connected = bleState is BleConnected;
        final busy = bleState is BleConnecting || bleState is BleScanning;
        final scheme = Theme.of(context).colorScheme;
        final color = connected
            ? AppColors.success
            : busy
            ? scheme.primary
            : AppColors.warning;
        final title = connected
            ? 'Live syncing'
            : busy
            ? 'Finding the clock'
            : 'Saved locally';
        final detail = connected
            ? 'Every display change applies right away.'
            : busy
            ? 'WakeGuard is re-establishing the Bluetooth link.'
            : 'Changes will apply the next time the clock connects.';

        return GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          borderRadius: 24,
          shadows: wakeCardShadow(context),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.34)),
                ),
                child: Icon(
                  connected
                      ? Icons.bolt_rounded
                      : busy
                      ? Icons.sync_rounded
                      : Icons.cloud_done_rounded,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12.5,
                        height: 1.28,
                      ),
                    ),
                  ],
                ),
              ),
              if (!connected && !busy) ...[
                const SizedBox(width: 10),
                TextButton.icon(
                  onPressed: () =>
                      context.read<BleConnectionBloc>().add(ReconnectEvent()),
                  icon: const Icon(Icons.bluetooth_searching_rounded, size: 16),
                  label: const Text('Reconnect'),
                  style: TextButton.styleFrom(
                    foregroundColor: color,
                    textStyle: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _presetSection(BuildContext context, SettingsState settings) {
    return WakeSection(
      title: 'Presets',
      subtitle: 'Fast starting points for different rooms and routines.',
      child: SizedBox(
        height: 116,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _presets.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            return SizedBox(
              width: 156,
              child: _presetTile(context, settings, _presets[index]),
            );
          },
        ),
      ),
    );
  }

  Widget _presetTile(
    BuildContext context,
    SettingsState settings,
    _DisplayPreset preset,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = preset.matches(settings);
    final accent = _accents[preset.accentIndex].color;
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.all(11),
      borderColor: selected ? accent.withValues(alpha: 0.82) : null,
      borderWidth: selected ? 1.6 : 1,
      tintColor: selected ? accent : null,
      shadows: selected ? wakeCardShadow(context) : null,
      onTap: () => _applyPreset(context, preset),
      child: SizedBox(
        height: 82,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: selected ? 0.24 : 0.16),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(preset.icon, color: accent, size: 17),
                ),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: accent, size: 18),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              preset.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              preset.description,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }

  void _applyPreset(BuildContext context, _DisplayPreset preset) {
    final bloc = context.read<SettingsBloc>();
    bloc.add(
      UpdateClockDisplayEvent(
        themeLight: preset.themeLight,
        accentIndex: preset.accentIndex,
        showSeconds: preset.showSeconds,
        showDate: preset.showDate,
        showDayOfWeek: preset.showDayOfWeek,
        dateFormat: preset.dateFormat,
      ),
    );
    bloc.add(ToggleShowWeatherEvent(preset.showWeather));
    bloc.add(
      UpdateClockSleepEvent(
        enabled: preset.sleepEnabled,
        startMinutes: preset.sleepStartMinutes,
        endMinutes: preset.sleepEndMinutes,
      ),
    );
  }

  Widget _appearanceSection(
    BuildContext context,
    SettingsState settings,
    _DisplayUpdate update,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return WakeSection(
      title: 'Appearance',
      subtitle: 'Face theme and the accent used for clock highlights.',
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 26,
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _modeSegment(
                  context,
                  label: 'Dark',
                  icon: Icons.dark_mode_rounded,
                  selected: !settings.clockThemeLight,
                  onTap: () => update(themeLight: false),
                ),
                const SizedBox(width: 10),
                _modeSegment(
                  context,
                  label: 'Light',
                  icon: Icons.light_mode_rounded,
                  selected: settings.clockThemeLight,
                  onTap: () => update(themeLight: true),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'Accent',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  _accents[settings.clockAccentIndex].name,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
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
          ],
        ),
      ),
    );
  }

  Widget _modeSegment(
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
            : scheme.surface.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? scheme.primary
                    : GlassTheme.of(context).stroke,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 19,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? scheme.onSurface : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: selected ? 0.48 : 0.22),
                    blurRadius: selected ? 14 : 8,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 22,
                    )
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _faceSection(
    BuildContext context,
    SettingsState settings,
    _DisplayUpdate update,
  ) {
    return WakeSection(
      title: 'Clock Face',
      subtitle: 'Choose the information density of the display.',
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 26,
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _subhead(context, 'Time Format'),
            const SizedBox(height: 10),
            _timeFormatControl(context, settings),
            const SizedBox(height: 18),
            _subhead(context, 'Visible Details'),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth < 360
                    ? constraints.maxWidth
                    : (constraints.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(
                      width: itemWidth,
                      child: _visualToggle(
                        context,
                        icon: Icons.timer_outlined,
                        title: 'Seconds',
                        subtitle: 'Show each tick',
                        selected: settings.clockShowSeconds,
                        onTap: () =>
                            update(showSeconds: !settings.clockShowSeconds),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _visualToggle(
                        context,
                        icon: Icons.today_rounded,
                        title: 'Day',
                        subtitle: 'Weekday line',
                        selected: settings.clockShowDayOfWeek,
                        onTap: () =>
                            update(showDayOfWeek: !settings.clockShowDayOfWeek),
                      ),
                    ),
                    SizedBox(
                      width: itemWidth,
                      child: _visualToggle(
                        context,
                        icon: Icons.calendar_today_rounded,
                        title: 'Date',
                        subtitle: 'Calendar line',
                        selected: settings.clockShowDate,
                        onTap: () => update(showDate: !settings.clockShowDate),
                      ),
                    ),
                  ],
                );
              },
            ),
            if (settings.clockShowDate) ...[
              const SizedBox(height: 18),
              _subhead(context, 'Date Format'),
              const SizedBox(height: 10),
              _dateFormatPicker(context, settings, update),
            ],
          ],
        ),
      ),
    );
  }

  Widget _subhead(BuildContext context, String label) {
    return Text(
      label,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _timeFormatControl(BuildContext context, SettingsState settings) {
    return Row(
      children: [
        _formatSegment(
          context,
          label: '12h',
          sample: '2:30 PM',
          selected: !settings.is24HourTime,
          onTap: () => context.read<SettingsBloc>().add(
            const Toggle24HourTimeEvent(false),
          ),
        ),
        const SizedBox(width: 10),
        _formatSegment(
          context,
          label: '24h',
          sample: '14:30',
          selected: settings.is24HourTime,
          onTap: () => context.read<SettingsBloc>().add(
            const Toggle24HourTimeEvent(true),
          ),
        ),
      ],
    );
  }

  Widget _formatSegment(
    BuildContext context, {
    required String label,
    required String sample,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.16)
                : scheme.surface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : GlassTheme.of(context).stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? scheme.primary : scheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                sample,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _visualToggle(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 96,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.15)
                : scheme.surface.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? scheme.primary : GlassTheme.of(context).stroke,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    size: 21,
                  ),
                  const Spacer(),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    size: 18,
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const List<String> _dateFormatSamples = [
    'Jul 8',
    '8 Jul',
    '07/08/26',
    '2026-07-08',
  ];

  Widget _dateFormatPicker(
    BuildContext context,
    SettingsState settings,
    _DisplayUpdate update,
  ) {
    return Wrap(
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
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: 1.3,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _nightModeSection(BuildContext context, SettingsState settings) {
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
      title: 'Night Mode',
      subtitle: 'Blank the display during quiet hours while alarms stay armed.',
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 26,
        shadows: wakeCardShadow(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    Icons.nights_stay_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        enabled ? 'Screen sleeps overnight' : 'Always on',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        enabled
                            ? _sleepSummary(settings)
                            : 'The clock face remains visible all night.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: enabled,
                  onChanged: (v) => dispatch(on: v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sleepPresetRow(context, settings, dispatch),
            if (enabled) ...[
              const SizedBox(height: 18),
              _sleepTimeline(context, settings, dispatch),
              const SizedBox(height: 14),
              _sleepHint(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sleepPresetRow(
    BuildContext context,
    SettingsState settings,
    void Function({bool? on, int? startMinutes, int? endMinutes}) dispatch,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _sleepPresetChip(
          context,
          label: 'Always On',
          selected: !settings.clockSleepEnabled,
          onTap: () => dispatch(on: false),
        ),
        _sleepPresetChip(
          context,
          label: 'Bedroom',
          selected:
              settings.clockSleepEnabled &&
              settings.clockSleepStartMinutes == 22 * 60 &&
              settings.clockSleepEndMinutes == 7 * 60,
          onTap: () =>
              dispatch(on: true, startMinutes: 22 * 60, endMinutes: 7 * 60),
        ),
        _sleepPresetChip(
          context,
          label: 'Late Night',
          selected:
              settings.clockSleepEnabled &&
              settings.clockSleepStartMinutes == 23 * 60 &&
              settings.clockSleepEndMinutes == 8 * 60,
          onTap: () =>
              dispatch(on: true, startMinutes: 23 * 60, endMinutes: 8 * 60),
        ),
      ],
    );
  }

  Widget _sleepPresetChip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _sleepTimeline(
    BuildContext context,
    SettingsState settings,
    void Function({bool? on, int? startMinutes, int? endMinutes}) dispatch,
  ) {
    return Row(
      children: [
        Expanded(
          child: _timeButton(
            context,
            settings,
            label: 'Sleep',
            icon: Icons.nightlight_round,
            minutes: settings.clockSleepStartMinutes,
            onPicked: (m) => dispatch(startMinutes: m),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Column(
            children: [
              Icon(
                Icons.arrow_forward_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
              const SizedBox(height: 4),
              Container(
                width: 34,
                height: 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _timeButton(
            context,
            settings,
            label: 'Wake',
            icon: Icons.wb_twilight_rounded,
            minutes: settings.clockSleepEndMinutes,
            onPicked: (m) => dispatch(endMinutes: m),
          ),
        ),
      ],
    );
  }

  Widget _timeButton(
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
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        );
        if (picked != null) onPicked(picked.hour * 60 + picked.minute);
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.42)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 17, color: scheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              display,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: scheme.primary,
                fontSize: 17,
                fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _sleepSummary(SettingsState settings) {
    final start = AlarmTimeUtils.formatTime(
      settings.clockSleepStartMinutes ~/ 60,
      settings.clockSleepStartMinutes % 60,
      is24Hour: settings.is24HourTime,
    );
    final end = AlarmTimeUtils.formatTime(
      settings.clockSleepEndMinutes ~/ 60,
      settings.clockSleepEndMinutes % 60,
      is24Hour: settings.is24HourTime,
    );
    return '$start - $end';
  }

  Widget _sleepHint(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 15,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'The face hides during this window. Alarms still wake the screen and ring.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }

  Widget _weatherSection(BuildContext context, SettingsState settings) {
    final bloc = context.read<SettingsBloc>();
    return WakeSection(
      title: 'Weather Corner',
      subtitle: 'A small condition glance in the top-right of the clock face.',
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        borderRadius: 26,
        shadows: wakeCardShadow(context),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.wb_sunny_rounded,
                    color: AppColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        settings.showWeather
                            ? 'Weather visible'
                            : 'Weather hidden',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settings.showWeather
                            ? 'Phone updates local conditions while connected.'
                            : 'The top-right corner stays clear.',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.showWeather,
                  onChanged: (v) => bloc.add(ToggleShowWeatherEvent(v)),
                ),
              ],
            ),
            if (settings.showWeather) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Temperature scale',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _unitToggle(context, settings),
                ],
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected
                ? scheme.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: 1.3,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        pill(
          '°C',
          !settings.weatherFahrenheit,
          () => bloc.add(const ToggleWeatherUnitEvent(false)),
        ),
        const SizedBox(width: 6),
        pill(
          '°F',
          settings.weatherFahrenheit,
          () => bloc.add(const ToggleWeatherUnitEvent(true)),
        ),
      ],
    );
  }

  Color _accentFor(SettingsState settings) {
    final safeIndex = settings.clockAccentIndex.clamp(0, _accents.length - 1);
    return _accents[safeIndex].color;
  }
}

class _ClockFacePreview extends StatelessWidget {
  final SettingsState settings;
  final Color accent;
  final bool connected;

  const _ClockFacePreview({
    required this.settings,
    required this.accent,
    required this.connected,
  });

  @override
  Widget build(BuildContext context) {
    final light = settings.clockThemeLight;
    final face = light ? const Color(0xFFF6F8FA) : const Color(0xFF111A20);
    final face2 = light ? const Color(0xFFE9EEF2) : const Color(0xFF1C2831);
    final text = light ? const Color(0xFF101820) : Colors.white;
    final muted = light ? const Color(0xFF5C6872) : Colors.white70;

    return AspectRatio(
      aspectRatio: 1.55,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [face, face2],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.34), width: 1.4),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.20),
              blurRadius: 26,
              spreadRadius: -16,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: StreamBuilder<DateTime>(
          stream: Stream<DateTime>.periodic(
            const Duration(seconds: 1),
            (_) => DateTime.now(),
          ),
          initialData: DateTime.now(),
          builder: (context, snapshot) {
            final now = snapshot.data ?? DateTime.now();
            final parts = _timeParts(now);
            final infoLine = _infoLine(now);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: connected ? AppColors.success : accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (connected ? AppColors.success : accent)
                                .withValues(alpha: 0.62),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'WakeGuard',
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const Spacer(),
                    if (settings.showWeather)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wb_sunny_rounded, color: accent, size: 17),
                          const SizedBox(width: 5),
                          Text(
                            settings.weatherFahrenheit ? '72°' : '22°',
                            style: TextStyle(
                              color: text,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                const Spacer(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        parts.main,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: text,
                          fontSize: settings.clockShowSeconds ? 38 : 44,
                          height: 0.95,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (parts.suffix != null) ...[
                      const SizedBox(width: 7),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          parts.suffix!,
                          style: TextStyle(
                            color: muted,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Text(
                    infoLine,
                    key: ValueKey(infoLine),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  _PreviewTimeParts _timeParts(DateTime now) {
    final seconds = settings.clockShowSeconds
        ? ':${now.second.toString().padLeft(2, '0')}'
        : '';
    if (settings.is24HourTime) {
      return _PreviewTimeParts(
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}$seconds',
      );
    }

    var hour = now.hour % 12;
    if (hour == 0) hour = 12;
    return _PreviewTimeParts(
      '$hour:${now.minute.toString().padLeft(2, '0')}$seconds',
      now.hour >= 12 ? 'PM' : 'AM',
    );
  }

  String _infoLine(DateTime now) {
    final parts = <String>[];
    if (settings.clockShowDayOfWeek) {
      const days = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      parts.add(days[now.weekday - 1]);
    }
    if (settings.clockShowDate) {
      parts.add(_formatDate(now));
    }
    return parts.isEmpty ? 'Ready for your next alarm' : parts.join('  •  ');
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final yy = (date.year % 100).toString().padLeft(2, '0');
    switch (settings.clockDateFormat) {
      case 1:
        return '${date.day} $month';
      case 2:
        return '$mm/$dd/$yy';
      case 3:
        return '${date.year}-$mm-$dd';
      case 0:
      default:
        return '$month ${date.day}';
    }
  }
}

class _PreviewTimeParts {
  final String main;
  final String? suffix;

  const _PreviewTimeParts(this.main, [this.suffix]);
}

class _DisplayPreset {
  final String name;
  final String description;
  final IconData icon;
  final bool themeLight;
  final int accentIndex;
  final bool showSeconds;
  final bool showDate;
  final bool showDayOfWeek;
  final int dateFormat;
  final bool showWeather;
  final bool sleepEnabled;
  final int sleepStartMinutes;
  final int sleepEndMinutes;

  const _DisplayPreset({
    required this.name,
    required this.description,
    required this.icon,
    required this.themeLight,
    required this.accentIndex,
    required this.showSeconds,
    required this.showDate,
    required this.showDayOfWeek,
    this.dateFormat = 0,
    required this.showWeather,
    required this.sleepEnabled,
    this.sleepStartMinutes = 22 * 60,
    this.sleepEndMinutes = 7 * 60,
  });

  bool matches(SettingsState settings) {
    return settings.clockThemeLight == themeLight &&
        settings.clockAccentIndex == accentIndex &&
        settings.clockShowSeconds == showSeconds &&
        settings.clockShowDate == showDate &&
        settings.clockShowDayOfWeek == showDayOfWeek &&
        settings.clockDateFormat == dateFormat &&
        settings.showWeather == showWeather &&
        settings.clockSleepEnabled == sleepEnabled &&
        (!sleepEnabled ||
            (settings.clockSleepStartMinutes == sleepStartMinutes &&
                settings.clockSleepEndMinutes == sleepEndMinutes));
  }
}
