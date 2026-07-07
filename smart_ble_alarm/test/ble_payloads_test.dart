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

      // 7-byte frame; bytes[5..6] are snooze allowance + length, both 0 here
      // (snooze disabled).
      expect(BlePayloads.alarm(alarm), [7, 6, 45, 0xBE, 1, 0, 0]);
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

      // byte[6] defaults to 5 minutes when the alarm doesn't override it.
      expect(BlePayloads.alarm(alarm), [3, 8, 0, 0x80, 0, 4, 5]);
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

      expect(BlePayloads.alarm(alarm), [3, 8, 0, 0x80, 0, 2, 10]);
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

      // Both snooze bytes collapse to 0 when the toggle is off.
      expect(BlePayloads.alarm(alarm), [3, 8, 0, 0x80, 0, 0, 0]);
    });

    test('encodes clock settings payload with minute precision', () {
      expect(
        BlePayloads.clockSettings(
          autoDim: true,
          sleepStartHour: 22,
          sleepStartMinute: 30,
          sleepEndHour: 6,
          sleepEndMinute: 15,
        ),
        [1, 22, 30, 6, 15],
      );
    });
  });
}
