import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/repositories/ble_repository.dart';
import '../../blocs/ble_bloc/ble_bloc.dart';
import '../../blocs/ble_bloc/ble_state.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../../../domain/entities/alarm.dart';
import '../alarm_edit_screen.dart';
import '../scanner_screen.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('DASHBOARD', style: TextStyle(color: AppColors.neonBlue, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 16),
              _buildConnectionStatus(),
              const SizedBox(height: 16),
              _buildNextAlarm(context),
              const SizedBox(height: 24),
              const Text('QUICK ACTIONS', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const SizedBox(height: 16),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  children: [
                    _buildActionCard(context, 'Create Alarm', Icons.add_alarm, () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AlarmEditScreen()));
                    }),
                    _buildActionCard(context, 'Start Timer', Icons.timer, () {
                      _showTimerDialog(context);
                    }),
                    // Mock ringing toggle for testing
                    _buildActionCard(context, 'Test Ringing', Icons.notifications_active, () {
                      final bloc = context.read<AlarmBloc>();
                      if (bloc.state.alarms.isNotEmpty) {
                        final currentRinging = bloc.state.ringingAlarmId;
                        bloc.add(SetRingingAlarmEvent(currentRinging == null ? bloc.state.alarms.first.id : null));
                      }
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return BlocBuilder<BleConnectionBloc, BleState>(
      builder: (context, state) {
        String status = 'Disconnected';
        String deviceName = 'No Device';
        Color color = AppColors.error;
        if (state is BleConnected) {
          status = 'Connected';
          deviceName = state.device.platformName;
          color = AppColors.success;
        } else if (state is BleConnecting || state is BleScanning) {
          status = 'Connecting...';
          color = AppColors.primaryOrange;
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.surfaceHighlight),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: Icon(Icons.bluetooth, color: color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(deviceName, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 18)),
                    Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    );
  }

  Widget _buildNextAlarm(BuildContext context) {
    return BlocBuilder<AlarmBloc, AlarmState>(
      builder: (context, alarmState) {
        if (alarmState.alarms.isEmpty) {
          return const SizedBox.shrink();
        }
        
        final activeAlarms = alarmState.alarms.where((a) => a.isActive).toList();
        if (activeAlarms.isEmpty) {
          return const SizedBox.shrink();
        }

        final now = DateTime.now();
        final currentMinutes = now.hour * 60 + now.minute;
        
        Alarm? nextAlarm;
        int smallestDiff = 24 * 60 + 1;
        
        for (var alarm in activeAlarms) {
          final alarmMinutes = alarm.hour * 60 + alarm.minute;
          int diff = alarmMinutes - currentMinutes;
          if (diff <= 0) diff += 24 * 60;
          
          if (diff < smallestDiff) {
            smallestDiff = diff;
            nextAlarm = alarm;
          }
        }
        
        if (nextAlarm == null) return const SizedBox.shrink();
        final Alarm activeNextAlarm = nextAlarm;
        final isRinging = alarmState.ringingAlarmId == activeNextAlarm.id;

        return BlocBuilder<SettingsBloc, SettingsState>(
          builder: (context, settingsState) {
            String m = activeNextAlarm.minute.toString().padLeft(2, '0');
            String timeStr = '';
            if (settingsState.is24HourTime) {
              timeStr = '${activeNextAlarm.hour.toString().padLeft(2, '0')}:$m';
            } else {
              int h = activeNextAlarm.hour % 12;
              if (h == 0) h = 12;
              String amPm = activeNextAlarm.hour >= 12 ? 'PM' : 'AM';
              timeStr = '${h.toString().padLeft(2, '0')}:$m $amPm';
            }

            return AnimatedContainer(
              duration: settingsState.animationsEnabled ? const Duration(milliseconds: 300) : Duration.zero,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isRinging ? AppColors.error.withValues(alpha: 0.2) : AppColors.primaryOrange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isRinging ? AppColors.error : AppColors.primaryOrange.withValues(alpha: 0.3), width: isRinging ? 2 : 1),
              ),
              child: isRinging 
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('ALARM RINGING', textAlign: TextAlign.center, style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, letterSpacing: 2, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text(timeStr, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, fontSize: 42, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        icon: const Icon(Icons.qr_code_scanner, size: 28),
                        label: const Text('SCAN QR TO DISMISS', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ScannerScreen(alarmId: activeNextAlarm.id)));
                        },
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('NEXT ALARM', style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          const SizedBox(height: 8),
                          Text(timeStr, style: const TextStyle(color: AppColors.textPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Icon(Icons.alarm_on, color: AppColors.primaryOrange.withValues(alpha: 0.5), size: 48),
                    ],
                  ),
            );
          }
        );
      }
    );
  }

  Widget _buildActionCard(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.surfaceHighlight),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.neonBlue, size: 32),
            const SizedBox(height: 12),
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _showTimerDialog(BuildContext context) {
    Duration selectedDuration = const Duration(minutes: 15);
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Theme.of(context).colorScheme.surface,
              title: const Text('Start Timer', style: TextStyle(color: AppColors.neonBlue)),
              content: SizedBox(
                height: 200,
                child: CupertinoTheme(
                  data: CupertinoThemeData(
                    brightness: Theme.of(context).brightness,
                    textTheme: CupertinoTextThemeData(
                      pickerTextStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 22,
                      ),
                    ),
                  ),
                  child: CupertinoTimerPicker(
                    mode: CupertinoTimerPickerMode.hms,
                    initialTimerDuration: selectedDuration,
                    onTimerDurationChanged: (Duration newDuration) {
                      setState(() {
                        selectedDuration = newDuration;
                      });
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.textSecondary)),
                ),
                TextButton(
                  onPressed: () {
                    final bleState = context.read<BleConnectionBloc>().state;
                    if (bleState is BleConnected) {
                      final durationSeconds = selectedDuration.inSeconds;
                      if (durationSeconds <= 0) return;
                      
                      final payload = [
                        (durationSeconds >> 24) & 0xFF,
                        (durationSeconds >> 16) & 0xFF,
                        (durationSeconds >> 8) & 0xFF,
                        durationSeconds & 0xFF,
                      ];
                      try {
                        context.read<BleRepository>().sendCommand(bleState.device, 0x0A, payload);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Timer started on clock!'), backgroundColor: AppColors.success));
                      } catch (_) {}
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not connected to clock'), backgroundColor: AppColors.error));
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('START', style: TextStyle(color: AppColors.primaryOrange, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
