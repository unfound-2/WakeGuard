import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/entities/alarm.dart';
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
  bool _qrRequired = true;
  bool _isOneTime = true;
  int _selectedDaysMask = 0; // Bit 0 = Sun, 1 = Mon, ..., 6 = Sat

  @override
  void initState() {
    super.initState();
    if (widget.alarm != null) {
      _selectedTime = TimeOfDay(hour: widget.alarm!.hour, minute: widget.alarm!.minute);
      _qrRequired = widget.alarm!.qrRequired;
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
      _qrRequired = context.read<SettingsBloc>().state.defaultQrRequired;
    }
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
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: Theme.of(context).brightness == Brightness.dark 
                    ? [AppColors.background, Colors.black]
                    : [AppColors.lightBackground, Colors.white],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildTimeSelector(settingsState.is24HourTime),
                    const SizedBox(height: 40),
                    _buildOptions(settingsState.animationsEnabled),
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryOrange,
                          shadowColor: AppColors.primaryOrange.withValues(alpha: 0.5),
                          elevation: 10,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        onPressed: () {
                          int finalDayMask = _isOneTime ? 0 : _selectedDaysMask;
                          final alarm = Alarm(
                            id: widget.alarm?.id ?? DateTime.now().millisecondsSinceEpoch % 1000,
                            hour: _selectedTime.hour,
                            minute: _selectedTime.minute,
                            dayMask: 0x80 | finalDayMask, // Active flag (0x80) + selected days
                            qrRequired: _qrRequired,
                          );
                          
                          final bleState = context.read<BleConnectionBloc>().state;
                          BluetoothDevice? device;
                          if (bleState is BleConnected) {
                            device = bleState.device;
                          }
                          
                          context.read<AlarmBloc>().add(AddOrUpdateAlarmEvent(alarm, device));
                          Navigator.pop(context);
                        },
                        child: const Text('SAVE SEQUENCE', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
                      ),
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

  Widget _buildTimeSelector(bool is24HourTime) {
    String formattedTime = _formatTime(_selectedTime.hour, _selectedTime.minute, is24HourTime);
    
    return GestureDetector(
      onTap: () async {
        final time = await showTimePicker(
          context: context,
          initialTime: _selectedTime,
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: is24HourTime),
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: const ColorScheme.dark(
                    primary: AppColors.primaryOrange,
                    onPrimary: Colors.white,
                    surface: AppColors.surface,
                    onSurface: AppColors.textPrimary,
                  ),
                ),
                child: child!,
              ),
            );
          },
        );
        if (time != null) setState(() => _selectedTime = time);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: AppColors.primaryOrange.withValues(alpha: 0.5), width: 2),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryOrange.withValues(alpha: 0.15),
              blurRadius: 30,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              formattedTime,
              style: const TextStyle(
                fontSize: 64, // Slightly smaller to fit AM/PM if needed
                fontWeight: FontWeight.bold,
                color: AppColors.neonBlue,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app, color: AppColors.primaryOrange, size: 20),
                const SizedBox(width: 8),
                const Text('TAP TO CHANGE TIME', style: TextStyle(color: AppColors.primaryOrange, letterSpacing: 2, fontWeight: FontWeight.w600)),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildOptions(bool animationsEnabled) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.surfaceHighlight, width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('One-Time Alarm', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Switch(
                    value: _isOneTime,
                    activeThumbColor: AppColors.neonBlue,
                    onChanged: (val) => setState(() => _isOneTime = val),
                  ),
                ],
              ),
              if (!_isOneTime) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Divider(color: AppColors.surfaceHighlight, height: 1),
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('REPEAT ON', style: TextStyle(color: AppColors.textSecondary, letterSpacing: 2, fontWeight: FontWeight.bold)),
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Divider(color: AppColors.surfaceHighlight, height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Require QR Scan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Switch(
                    value: _qrRequired,
                    activeThumbColor: AppColors.primaryOrange,
                    onChanged: (val) => setState(() => _qrRequired = val),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dayChip(String label, int bit, bool animationsEnabled) {
    bool isSelected = (_selectedDaysMask & (1 << bit)) != 0;
    return GestureDetector(
      onTap: () => _toggleDay(bit),
      child: AnimatedContainer(
        duration: animationsEnabled ? const Duration(milliseconds: 200) : Duration.zero,
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isSelected ? AppColors.neonBlue.withValues(alpha: 0.2) : AppColors.surfaceHighlight.withValues(alpha: 0.3),
          border: Border.all(
            color: isSelected ? AppColors.neonBlue : Colors.transparent,
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: AppColors.neonBlue.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 1,
            )
          ] : [],
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            color: isSelected ? AppColors.neonBlue : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  String _formatTime(int hour, int minute, bool is24Hour) {
    String m = minute.toString().padLeft(2, '0');
    if (is24Hour) {
      return '${hour.toString().padLeft(2, '0')}:$m';
    } else {
      int h = hour % 12;
      if (h == 0) h = 12;
      String amPm = hour >= 12 ? 'PM' : 'AM';
      return '${h.toString().padLeft(2, '0')}:$m $amPm';
    }
  }
}
