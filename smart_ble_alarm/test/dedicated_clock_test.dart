import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_ble_alarm/core/audio/alarm_sound.dart';
import 'package:smart_ble_alarm/presentation/blocs/settings_bloc/settings_bloc.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('alarm tone synthesis', () {
    test('buildAlarmToneWav emits a valid non-empty PCM WAV', () {
      final wav = buildAlarmToneWav();
      // Canonical RIFF/WAVE header + real audio payload past the 44-byte header.
      expect(wav.length, greaterThan(44));
      expect(ascii.decode(wav.sublist(0, 4)), 'RIFF');
      expect(ascii.decode(wav.sublist(8, 12)), 'WAVE');
      expect(ascii.decode(wav.sublist(12, 16)), 'fmt ');
    });
  });

  group('Dedicated Clock mode', () {
    test('dedicatedClockEnabled defaults to false and loads from prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final bloc = SettingsBloc(prefs: prefs)..add(LoadSettingsEvent());
      await bloc.stream.first;
      expect(bloc.state.dedicatedClockEnabled, isFalse);
      await bloc.close();
    });

    test('a stored dedicatedClockEnabled=true is loaded back', () async {
      SharedPreferences.setMockInitialValues({'dedicatedClockEnabled': true});
      final prefs = await SharedPreferences.getInstance();
      final bloc = SettingsBloc(prefs: prefs)..add(LoadSettingsEvent());
      await bloc.stream.first;
      expect(bloc.state.dedicatedClockEnabled, isTrue);
      await bloc.close();
    });

    test('ToggleDedicatedClockEvent persists and reflects the flag', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final bloc = SettingsBloc(prefs: prefs);
      bloc.add(const ToggleDedicatedClockEvent(true));
      await bloc.stream.firstWhere((s) => s.dedicatedClockEnabled);
      expect(prefs.getBool('dedicatedClockEnabled'), isTrue);
      await bloc.close();
    });
  });
}
