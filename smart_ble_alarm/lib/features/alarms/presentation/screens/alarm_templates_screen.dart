import 'package:flutter/material.dart';

import 'package:smart_ble_alarm/core/theme/glass.dart';
import 'package:smart_ble_alarm/core/theme/wake_widgets.dart';
import 'package:smart_ble_alarm/core/ui/wake_haptics.dart';
import 'package:smart_ble_alarm/features/alarms/presentation/screens/alarm_edit_screen.dart';

/// A ready-made alarm routine. Tapping one opens the alarm editor pre-filled
/// with the template's time, repeat days, and label so the user only has to
/// fine-tune before saving.
class _AlarmTemplate {
  final String label;
  final String subtitle;
  final IconData icon;
  final int hour;
  final int minute;
  final int repeatMask;

  const _AlarmTemplate({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.hour,
    required this.minute,
    required this.repeatMask,
  });
}

/// Dedicated page listing the alarm templates. Reached from the Alarms tab via
/// the "+" button → Templates. Previously the templates lived in a horizontal
/// strip on the Alarms list itself; they now have their own focused screen.
class AlarmTemplatesScreen extends StatelessWidget {
  const AlarmTemplatesScreen({super.key});

  static const List<_AlarmTemplate> _templates = [
    _AlarmTemplate(
      label: 'Workday',
      subtitle: 'Mon-Fri',
      icon: Icons.work_rounded,
      hour: 7,
      minute: 0,
      repeatMask: 0x3E,
    ),
    _AlarmTemplate(
      label: 'Medication',
      subtitle: 'Daily',
      icon: Icons.medication_rounded,
      hour: 8,
      minute: 0,
      repeatMask: 0x7F,
    ),
    _AlarmTemplate(
      label: 'School',
      subtitle: 'Weekdays',
      icon: Icons.school_rounded,
      hour: 6,
      minute: 30,
      repeatMask: 0x3E,
    ),
    _AlarmTemplate(
      label: 'Weekend',
      subtitle: 'Sat-Sun',
      icon: Icons.weekend_rounded,
      hour: 9,
      minute: 0,
      repeatMask: 0x41,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('TEMPLATES')),
      body: GlassBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              WakeSection(
                title: 'Start with a routine',
                subtitle: 'Pick a template, then tune the details before saving.',
                child: Column(
                  children: [
                    for (var i = 0; i < _templates.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _TemplateCard(
                        template: _templates[i],
                        onTap: () => _openTemplate(context, _templates[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTemplate(BuildContext context, _AlarmTemplate template) {
    WakeHaptics.lightImpact();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlarmEditScreen(
          initialLabel: template.label,
          initialTime: TimeOfDay(hour: template.hour, minute: template.minute),
          initialRepeatMask: template.repeatMask,
          initialQrRequired: true,
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final _AlarmTemplate template;
  final VoidCallback onTap;

  const _TemplateCard({required this.template, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      borderRadius: 22,
      padding: const EdgeInsets.all(16),
      shadows: wakeCardShadow(context),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(template.icon, size: 24, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  template.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.chevron_right_rounded,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.62),
            size: 20,
          ),
        ],
      ),
    );
  }
}
