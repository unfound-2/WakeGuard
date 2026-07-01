import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/alarm_bloc/alarm_bloc.dart';
import '../../blocs/settings_bloc/settings_bloc.dart';
import '../alarm_edit_screen.dart';
import '../scanner_screen.dart';
import '../../../domain/usecases/print_qr_code.dart';
import '../../../data/datasources/secure_key_datasource.dart';

class AlarmsTab extends StatelessWidget {
  const AlarmsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: Theme.of(context).brightness == Brightness.dark 
                ? [(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F111A) : const Color(0xFFF3F4F6)), Colors.black]
                : [(Theme.of(context).brightness == Brightness.dark ? const Color(0xFF0F111A) : const Color(0xFFF3F4F6)), Colors.white],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: TabBar(
                  indicatorColor: Theme.of(context).colorScheme.primary,
                  labelColor: Theme.of(context).colorScheme.primary,
                  unselectedLabelColor: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8B9BB4) : const Color(0xFF6B7280)),
                  tabs: const [
                    Tab(text: 'ALARMS'),
                    Tab(text: 'TIMERS'),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildAlarmsList(),
                    _buildTimersList(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimersList(BuildContext context) {
    return Center(
      child: Text(
        'No active timers.',
        style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8B9BB4) : const Color(0xFF6B7280)), fontSize: 16),
      ),
    );
  }

  Widget _buildAlarmsList() {
    return BlocBuilder<SettingsBloc, SettingsState>(
      builder: (context, settingsState) {
        return BlocBuilder<AlarmBloc, AlarmState>(
          builder: (context, state) {
            if (state.alarms.isEmpty) {
              return Center(
                child: Text('No alarms yet. Tap + to add one.', style: TextStyle(color: (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF8B9BB4) : const Color(0xFF6B7280)))),
              );
            }

            return Stack(
              children: [
                ListView.builder(
                  padding: const EdgeInsets.all(16).copyWith(bottom: 100),
                  itemCount: state.alarms.length,
                  itemBuilder: (context, index) {
                    final alarm = state.alarms[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => AlarmEditScreen(alarm: alarm)));
                        },
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatTime(alarm.hour, alarm.minute, settingsState.is24HourTime),
                                    style: TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onSurface,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _formatDays(alarm.dayMask),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.primary,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  if (alarm.qrRequired) ...[
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        OutlinedButton.icon(
                                          icon: const Icon(Icons.print, size: 16, color: Colors.white),
                                          label: const Text('Print QR', style: TextStyle(color: Colors.white)),
                                          style: OutlinedButton.styleFrom(
                                            side: BorderSide(color: Theme.of(context).dividerColor),
                                          ),
                                          onPressed: () async {
                                            final usecase = PrintQrCodeUseCase(
                                                secureKeyDatasource: SecureKeyDatasource());
                                            await usecase.execute(alarm.id);
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.qr_code_scanner, size: 16, color: Colors.white),
                                          label: const Text('Dismiss', style: TextStyle(color: Colors.white)),
                                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ScannerScreen(alarmId: alarm.id),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              Switch(
                                value: (alarm.dayMask & 0x80) != 0,
                                activeThumbColor: Theme.of(context).colorScheme.primary,
                                onChanged: (val) {
                                  // Toggle logic here
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const AlarmEditScreen()));
                    },
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
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

  String _formatDays(int dayMask) {
    if ((dayMask & 0x7F) == 0) return 'ONE-TIME';
    List<String> orderedDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    List<int> bits = [1, 2, 3, 4, 5, 6, 0];
    
    String finalResult = '';
    for (int i = 0; i < 7; i++) {
      if ((dayMask & (1 << bits[i])) != 0) {
        finalResult += '${orderedDays[i]} ';
      } else {
        finalResult += '- ';
      }
    }
    return finalResult.trim();
  }
}
