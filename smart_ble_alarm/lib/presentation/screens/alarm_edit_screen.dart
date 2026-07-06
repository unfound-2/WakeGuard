import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/wake_widgets.dart';
import '../../data/datasources/image_recognition_datasource.dart';
import '../../data/datasources/secure_key_datasource.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/usecases/print_qr_code.dart';
import '../blocs/alarm_bloc/alarm_bloc.dart';
import '../blocs/ble_bloc/ble_bloc.dart';
import '../blocs/ble_bloc/ble_state.dart';
import '../blocs/settings_bloc/settings_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AlarmEditScreen extends StatefulWidget {
  final Alarm? alarm;
  const AlarmEditScreen({super.key, this.alarm});

  @override
  State<AlarmEditScreen> createState() => _AlarmEditScreenState();
}

class _AlarmEditScreenState extends State<AlarmEditScreen> {
  late TimeOfDay _selectedTime;
  bool _requireDismissalTask = true;
  bool _useItemScan = false;
  String? _itemLabel;
  final TextEditingController _labelController = TextEditingController();
  bool _snoozeEnabled = false;
  int _snoozeMaxCount = 3;
  final TextEditingController _itemDescriptionController =
      TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ImageRecognitionDatasource _recognizer = ImageRecognitionDatasource();
  bool _capturing = false;
  bool _isOneTime = true;
  int _selectedDaysMask = 0; // Bit 0 = Sun, 1 = Mon, ..., 6 = Sat

  @override
  void initState() {
    super.initState();
    if (widget.alarm != null) {
      _selectedTime = TimeOfDay(
        hour: widget.alarm!.hour,
        minute: widget.alarm!.minute,
      );
      _requireDismissalTask = widget.alarm!.qrRequired;
      _useItemScan = widget.alarm!.usesItemScan;
      _itemLabel = widget.alarm!.itemLabel;
      _labelController.text = widget.alarm!.label ?? '';
      _snoozeEnabled = widget.alarm!.snoozeEnabled;
      if (widget.alarm!.snoozeMaxCount > 0) {
        _snoozeMaxCount = widget.alarm!.snoozeMaxCount;
      }
      _itemDescriptionController.text = widget.alarm!.itemDescription ?? '';
      int dayMask = widget.alarm!.dayMask & 0x7F;
      if (dayMask == 0) {
        _isOneTime = true;
        _selectedDaysMask = 0;
      } else {
        _isOneTime = false;
        _selectedDaysMask = dayMask;
      }
    } else {
      _selectedTime = TimeOfDay.now();
      _isOneTime = true;
      _selectedDaysMask = 0;
      final settings = context.read<SettingsBloc>().state;
      _requireDismissalTask = settings.defaultQrRequired;
      // Seed the per-alarm object from the global "default wake object" so a
      // new object-verification alarm starts with the user's chosen object
      // (still changeable below). Only persisted if item verification is on,
      // so this is a harmless default for QR/no-challenge alarms.
      _itemLabel = settings.wakeObjectName;
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    _itemDescriptionController.dispose();
    _recognizer.close();
    super.dispose();
  }

  void _toggleDay(int bit) {
    setState(() {
      _selectedDaysMask ^= (1 << bit);
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: Text(widget.alarm == null ? 'NEW ALARM' : 'EDIT ALARM'),
          ),
          body: GlassBackground(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            const SizedBox(height: 20),
                            _buildTimeWheel(settingsState),
                            const SizedBox(height: 24),
                            _buildOptions(settingsState.animationsEnabled),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    WakePrimaryButton(
                      label: widget.alarm == null ? 'Save Alarm' : 'Save Changes',
                      icon: Icons.check_rounded,
                      onPressed: () {
                        final alarmBloc = context.read<AlarmBloc>();
                        if (widget.alarm == null &&
                            alarmBloc.state.alarms.length >=
                                AlarmBloc.maxHardwareAlarms) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'The clock supports up to 5 alarms. Delete one before adding another.',
                              ),
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                          );
                          return;
                        }

                        if (!_isOneTime && _selectedDaysMask == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Choose at least one repeat day, or switch back to one-time.',
                              ),
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                          );
                          return;
                        }

                        final bool requiresItem =
                            _requireDismissalTask && _useItemScan;
                        if (requiresItem &&
                            (_itemLabel == null || _itemLabel!.isEmpty)) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Photograph the item this alarm should require first.',
                              ),
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                          );
                          return;
                        }

                        int finalDayMask = _isOneTime ? 0 : _selectedDaysMask;
                        final String description =
                            _itemDescriptionController.text.trim();
                        final String labelText = _labelController.text.trim();
                        final alarm = Alarm(
                          id:
                              widget.alarm?.id ??
                              _nextAlarmId(alarmBloc.state.alarms),
                          hour: _selectedTime.hour,
                          minute: _selectedTime.minute,
                          dayMask:
                              0x80 |
                              finalDayMask, // Active flag (0x80) + selected days
                          qrRequired: _requireDismissalTask,
                          itemLabel: requiresItem ? _itemLabel : null,
                          itemDescription: requiresItem && description.isNotEmpty
                              ? description
                              : null,
                          label: labelText.isNotEmpty ? labelText : null,
                          snoozeEnabled: _snoozeEnabled,
                          snoozeMaxCount: _snoozeEnabled ? _snoozeMaxCount : 0,
                        );

                        HapticFeedback.mediumImpact();

                        final bleState =
                            context.read<BleConnectionBloc>().state;
                        BluetoothDevice? device;
                        if (bleState is BleConnected) {
                          device = bleState.device;
                        }

                        alarmBloc.add(
                          AddOrUpdateAlarmEvent(
                            alarm,
                            device,
                            // Fresh alarm → fresh dismissal key. Edits keep
                            // the existing key (and any printed QR valid).
                            rotateSecureKey: widget.alarm == null,
                          ),
                        );
                        Navigator.pop(context);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTimeWheel(SettingsState settingsState) {
    return GlassCard(
      borderRadius: 28,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      child: _TimeWheelPicker(
        key: ValueKey('time-wheel-${settingsState.is24HourTime}'),
        hour: _selectedTime.hour,
        minute: _selectedTime.minute,
        is24Hour: settingsState.is24HourTime,
        animationsEnabled: settingsState.animationsEnabled,
        onChanged: (hour, minute) {
          setState(() => _selectedTime = TimeOfDay(hour: hour, minute: minute));
        },
      ),
    );
  }

  Widget _buildOptions(bool animationsEnabled) {
    return Column(
      children: [
        WakeSection(
          title: 'Details',
          child: GlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            shadows: wakeCardShadow(context),
            child: TextField(
              controller: _labelController,
              textCapitalization: TextCapitalization.sentences,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              decoration: InputDecoration(
                labelText: 'Label (optional)',
                hintText: 'e.g. Wake up, Meds, Work',
                labelStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                prefixIcon: Icon(
                  Icons.label_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        WakeSection(
          title: 'Repeat',
          child: GlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            shadows: wakeCardShadow(context),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'One-Time Alarm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Switch(
                      value: _isOneTime,
                      onChanged: (val) => setState(() => _isOneTime = val),
                    ),
                  ],
                ),
                if (!_isOneTime) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(
                      color: Theme.of(context).dividerColor,
                      height: 1,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'REPEAT ON',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _dayChip('M', 1, animationsEnabled),
                      _dayChip('T', 2, animationsEnabled),
                      _dayChip('W', 3, animationsEnabled),
                      _dayChip('T', 4, animationsEnabled),
                      _dayChip('F', 5, animationsEnabled),
                      _dayChip('S', 6, animationsEnabled),
                      _dayChip('S', 0, animationsEnabled),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        WakeSection(
          title: 'Wake Challenge',
          subtitle: 'Require a task before this alarm can be dismissed.',
          child: GlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            shadows: wakeCardShadow(context),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Require Dismissal Task',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Switch(
                      value: _requireDismissalTask,
                      onChanged: (val) =>
                          setState(() => _requireDismissalTask = val),
                    ),
                  ],
                ),
                if (_requireDismissalTask) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _methodChip(
                          'QR Code',
                          Icons.qr_code,
                          !_useItemScan,
                          () => setState(() => _useItemScan = false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _methodChip(
                          'Scan Item',
                          Icons.center_focus_strong,
                          _useItemScan,
                          () => setState(() => _useItemScan = true),
                        ),
                      ),
                    ],
                  ),
                  if (_useItemScan) ...[
                    const SizedBox(height: 16),
                    _buildItemCapture(),
                  ],
                  // Existing QR alarms can reprint their backup code here; new
                  // alarms get a code once saved. Item-scan alarms have no code.
                  if (!_useItemScan && widget.alarm != null) ...[
                    const SizedBox(height: 16),
                    WakeSecondaryButton(
                      label: 'Print backup code',
                      icon: Icons.print_rounded,
                      onPressed: () => _printCode(widget.alarm!.id),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        WakeSection(
          title: 'Snooze',
          child: GlassCard(
            borderRadius: 24,
            padding: const EdgeInsets.all(20),
            shadows: wakeCardShadow(context),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Allow Snooze',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Saved with this alarm. Snoozing is handled by the '
                            'clock hardware — this preference isn\'t sent over '
                            'Bluetooth yet.',
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
                    Switch(
                      value: _snoozeEnabled,
                      onChanged: (val) {
                        HapticFeedback.selectionClick();
                        setState(() => _snoozeEnabled = val);
                      },
                    ),
                  ],
                ),
                if (_snoozeEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: Divider(
                      color: Theme.of(context).dividerColor,
                      height: 1,
                    ),
                  ),
                  _buildSnoozeCountStepper(),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSnoozeCountStepper() {
    final primary = Theme.of(context).colorScheme.primary;
    const int minCount = 1;
    const int maxCount = 10;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Max snoozes',
          style: TextStyle(
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Row(
          children: [
            IconButton(
              onPressed: _snoozeMaxCount > minCount
                  ? () {
                      HapticFeedback.selectionClick();
                      setState(() => _snoozeMaxCount--);
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
              color: primary,
              tooltip: 'Fewer snoozes',
            ),
            SizedBox(
              width: 32,
              child: Text(
                '$_snoozeMaxCount',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            IconButton(
              onPressed: _snoozeMaxCount < maxCount
                  ? () {
                      HapticFeedback.selectionClick();
                      setState(() => _snoozeMaxCount++);
                    }
                  : null,
              icon: const Icon(Icons.add_circle_outline),
              color: primary,
              tooltip: 'More snoozes',
            ),
          ],
        ),
      ],
    );
  }

  Widget _dayChip(String label, int bit, bool animationsEnabled) {
    bool isSelected = (_selectedDaysMask & (1 << bit)) != 0;
    return Semantics(
      button: true,
      selected: isSelected,
      label: '$label repeat day',
      child: GestureDetector(
        onTap: () => _toggleDay(bit),
        child: AnimatedContainer(
          duration: animationsEnabled
              ? const Duration(milliseconds: 200)
              : Duration.zero,
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                : Theme.of(context).dividerColor.withValues(alpha: 0.3),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _printCode(int alarmId) async {
    final usecase = PrintQrCodeUseCase(
      secureKeyDatasource: SecureKeyDatasource(),
    );
    try {
      await usecase.execute(alarmId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Unable to open the print dialog.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Widget _methodChip(
    String label,
    IconData icon,
    bool selected,
    VoidCallback onTap,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? primary : Theme.of(context).dividerColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: selected
                  ? primary
                  : Theme.of(context).colorScheme.onSurface,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? primary
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCapture() {
    final hasItem = _itemLabel != null && _itemLabel!.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasItem) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: WakeStatusPill(
              label: 'Item: $_itemLabel',
              icon: Icons.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _capturing ? null : _captureItem,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.6),
              ),
            ),
            icon: _capturing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.photo_camera,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            label: Text(
              hasItem ? 'Change item photo' : 'Photograph the item',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _itemDescriptionController,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            labelText: 'Reminder (e.g. "toothbrush in the bathroom")',
            labelStyle: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            border: const OutlineInputBorder(),
          ),
        ),
      ],
    );
  }

  Future<void> _captureItem() async {
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1280,
    );
    if (photo == null || !mounted) return;
    setState(() => _capturing = true);
    try {
      final detected = await _recognizer.labelImageFile(photo.path);
      if (!mounted) return;
      setState(() => _capturing = false);
      if (detected.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Nothing recognised. Center the item and try again.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }
      await _showLabelPicker(detected);
    } catch (_) {
      if (!mounted) return;
      setState(() => _capturing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not process the photo. Try again.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _showLabelPicker(List<RecognizedItem> detected) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Which item is this?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
              for (final item in detected.take(5))
                ListTile(
                  leading: Icon(
                    Icons.label_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  trailing: Text('${(item.confidence * 100).round()}%'),
                  onTap: () => Navigator.pop(sheetContext, item.label),
                ),
            ],
          ),
        );
      },
    );
    if (choice != null && mounted) {
      setState(() => _itemLabel = choice);
    }
  }

  int _nextAlarmId(List<Alarm> alarms) {
    final usedIds = alarms.map((alarm) => alarm.id).toSet();
    for (var id = 1; id <= 255; id++) {
      if (!usedIds.contains(id)) return id;
    }

    throw StateError('No alarm identifiers are available.');
  }
}

/// Inline Apple-style time wheel used in the alarm editor. Two Cupertino wheels
/// (hour + minute) share one liquid-glass selection band; an AM/PM slider is
/// shown only in 12-hour mode. Time is always reported back in 24-hour form.
class _TimeWheelPicker extends StatefulWidget {
  final int hour; // 0-23 (source of truth)
  final int minute;
  final bool is24Hour;
  final bool animationsEnabled;
  final void Function(int hour, int minute) onChanged;

  const _TimeWheelPicker({
    super.key,
    required this.hour,
    required this.minute,
    required this.is24Hour,
    required this.animationsEnabled,
    required this.onChanged,
  });

  @override
  State<_TimeWheelPicker> createState() => _TimeWheelPickerState();
}

class _TimeWheelPickerState extends State<_TimeWheelPicker> {
  static const double _itemExtent = 44;

  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;
  late int _hourIndex;
  late int _minuteIndex;
  late bool _isPm;

  int _to12(int hour24) {
    final h = hour24 % 12;
    return h == 0 ? 12 : h;
  }

  int _to24(int display12, bool isPm) {
    final base = display12 % 12; // 12 -> 0
    return isPm ? base + 12 : base;
  }

  @override
  void initState() {
    super.initState();
    _isPm = widget.hour >= 12;
    _minuteIndex = widget.minute;
    _hourIndex = widget.is24Hour ? widget.hour : _to12(widget.hour) - 1;
    _hourController = FixedExtentScrollController(initialItem: _hourIndex);
    _minuteController = FixedExtentScrollController(initialItem: _minuteIndex);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _haptic() {
    if (widget.animationsEnabled) HapticFeedback.selectionClick();
  }

  void _emit() {
    final int hour24 = widget.is24Hour
        ? _hourIndex
        : _to24(_hourIndex + 1, _isPm);
    widget.onChanged(hour24, _minuteIndex);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final primary = theme.colorScheme.primary;
    final numberStyle = TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w500,
      color: onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final hourCount = widget.is24Hour ? 24 : 12;

    // Hour + minute wheels sharing one liquid-glass selection band. Both wheels
    // are the same width and zero-padded to two digits so the numbers sit at a
    // consistent rhythm, and the gap between them is wide enough to read as two
    // separate values rather than a single run of digits.
    final wheels = SizedBox(
      height: 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          IgnorePointer(
            child: Container(
              height: _itemExtent,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: primary.withValues(alpha: 0.18)),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _wheel(
                controller: _hourController,
                itemCount: hourCount,
                label: (i) => widget.is24Hour
                    ? i.toString().padLeft(2, '0')
                    : (i + 1).toString().padLeft(2, '0'),
                numberStyle: numberStyle,
                onSel: (i) {
                  _hourIndex = i;
                  _haptic();
                  _emit();
                },
              ),
              const SizedBox(width: 32),
              _wheel(
                controller: _minuteController,
                itemCount: 60,
                label: (i) => i.toString().padLeft(2, '0'),
                numberStyle: numberStyle,
                onSel: (i) {
                  _minuteIndex = i;
                  _haptic();
                  _emit();
                },
              ),
            ],
          ),
        ],
      ),
    );

    // In 12-hour mode the AM/PM control sits directly beside the numbers as a
    // vertical slider (matching the accent-thumb style of the other segmented
    // controls); 24-hour mode drops it entirely.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: wheels),
        if (!widget.is24Hour) ...[
          const SizedBox(width: 20),
          _amPmSlider(onSurface, primary),
        ],
      ],
    );
  }

  /// Vertical AM/PM slider: a rounded track with an accent thumb that slides
  /// between the two stacked segments. Mirrors the look of the horizontal
  /// segmented controls used elsewhere, rotated to sit next to the wheels.
  Widget _amPmSlider(Color onSurface, Color primary) {
    const double segW = 58;
    const double segH = 40;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: SizedBox(
        width: segW,
        height: segH * 2,
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: _isPm ? Alignment.bottomCenter : Alignment.topCenter,
              child: Container(
                width: segW,
                height: segH,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _amPmSegment(
                  'AM',
                  isPm: false,
                  selected: !_isPm,
                  width: segW,
                  height: segH,
                  onSurface: onSurface,
                ),
                _amPmSegment(
                  'PM',
                  isPm: true,
                  selected: _isPm,
                  width: segW,
                  height: segH,
                  onSurface: onSurface,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _amPmSegment(
    String text, {
    required bool isPm,
    required bool selected,
    required double width,
    required double height,
    required Color onSurface,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isPm == isPm) return;
        setState(() => _isPm = isPm);
        _haptic();
        _emit();
      },
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int) label,
    required TextStyle numberStyle,
    required ValueChanged<int> onSel,
  }) {
    return SizedBox(
      width: 60,
      height: 180,
      child: CupertinoPicker(
        scrollController: controller,
        itemExtent: _itemExtent,
        squeeze: 1.1,
        diameterRatio: 1.35,
        useMagnifier: true,
        magnification: 1.06,
        backgroundColor: Colors.transparent,
        selectionOverlay: const SizedBox.shrink(),
        onSelectedItemChanged: onSel,
        children: [
          for (int i = 0; i < itemCount; i++)
            Center(child: Text(label(i), style: numberStyle)),
        ],
      ),
    );
  }
}
