import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ble_alarm/core/ble/ble_payloads.dart';
import 'package:smart_ble_alarm/domain/entities/alarm.dart';

void main() {
  group('BlePayloads', () {
    test('encodes uint32 values big-endian for clock firmware', () {
      expect(BlePayloads.uint32(0x12345678), [0x12, 0x34, 0x56, 0x78]);
    });

    test('encodes alarm payload according to the HM-10 protocol', () {
      const alarm = Alarm(
        id: 7,
        hour: 6,
        minute: 45,
        dayMask: 0x80 | 0x3E,
        qrRequired: true,
      );

      // 9-byte frame; bytes[5..6] are snooze allowance + length (both 0 here,
      // snooze disabled), bytes[7..8] are volume + gradual-wake fade (the 80%
      // default and no fade).
      expect(BlePayloads.alarm(alarm), [7, 6, 45, 0xBE, 1, 0, 0, 80, 0]);
    });

    test('encodes the per-alarm snooze allowance in byte 5', () {
      const alarm = Alarm(
        id: 3,
        hour: 8,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
        snoozeEnabled: true,
        snoozeMaxCount: 4,
      );

      // byte[6] defaults to 5 minutes when the alarm doesn't override it;
      // bytes[7..8] carry the default 80% volume and no fade.
      expect(BlePayloads.alarm(alarm), [3, 8, 0, 0x80, 0, 4, 5, 80, 0]);
    });

    test('encodes the per-alarm snooze length in byte 6', () {
      const alarm = Alarm(
        id: 3,
        hour: 8,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
        snoozeEnabled: true,
        snoozeMaxCount: 2,
        snoozeDurationMinutes: 10,
      );

      expect(BlePayloads.alarm(alarm), [3, 8, 0, 0x80, 0, 2, 10, 80, 0]);
    });

    test('encodes ring volume in byte 7 and gradual-wake fade in byte 8', () {
      const alarm = Alarm(
        id: 5,
        hour: 7,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
        volumePercent: 60,
        gradualWakeSeconds: 30,
      );

      // Volume + fade travel independently of snooze (bytes[5..6] stay 0 here).
      expect(BlePayloads.alarm(alarm), [5, 7, 0, 0x80, 0, 0, 0, 60, 30]);
    });

    test('clamps volume into the 1..100 wire range', () {
      const silent = Alarm(
        id: 5,
        hour: 7,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
        volumePercent: 0,
      );
      const tooLoud = Alarm(
        id: 5,
        hour: 7,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
        volumePercent: 150,
      );

      // 0 would read as "clock default" on the firmware, and >100 is meaningless;
      // the wire byte is clamped so a corrupt value can't silence or overflow it.
      expect(BlePayloads.alarm(silent)[7], 1);
      expect(BlePayloads.alarm(tooLoud)[7], 100);
    });

    test('sends snooze count 0 when snooze is disabled', () {
      // snoozeMaxCount is retained app-side but must not travel while the toggle
      // is off — the clock reads 0 as "no snoozing".
      const alarm = Alarm(
        id: 3,
        hour: 8,
        minute: 0,
        dayMask: 0x80,
        qrRequired: false,
        snoozeEnabled: false,
        snoozeMaxCount: 4,
      );

      // Both snooze bytes collapse to 0 when the toggle is off; volume + fade
      // keep their defaults (80%, no fade).
      expect(BlePayloads.alarm(alarm), [3, 8, 0, 0x80, 0, 0, 0, 80, 0]);
    });

    test('packs clock display settings into [flags, theme, accent]', () {
      // flags bit0=24h, bit1=seconds, bit2=date. Here: 24h + date, no seconds
      // => 0b101 = 5; dark theme (0); amber accent (0).
      expect(
        BlePayloads.clockDisplaySettings(
          use24h: true,
          showSeconds: false,
          showDate: true,
          theme: 0,
          accent: 0,
        ),
        [5, 0, 0],
      );
      // Everything on, light theme, violet accent.
      expect(
        BlePayloads.clockDisplaySettings(
          use24h: true,
          showSeconds: true,
          showDate: true,
          theme: 1,
          accent: 3,
        ),
        [7, 1, 3],
      );
      // 12-hour, nothing else: all flag bits clear.
      expect(
        BlePayloads.clockDisplaySettings(
          use24h: false,
          showSeconds: false,
          showDate: false,
          theme: 0,
          accent: 1,
        ),
        [0, 0, 1],
      );
    });
  });
}
