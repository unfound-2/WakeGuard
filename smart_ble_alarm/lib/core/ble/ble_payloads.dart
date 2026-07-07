import '../../domain/entities/alarm.dart';

class BlePayloads {
  const BlePayloads._();

  static List<int> uint32(int value) {
    final normalized = value & 0xFFFFFFFF;
    return [
      (normalized >> 24) & 0xFF,
      (normalized >> 16) & 0xFF,
      (normalized >> 8) & 0xFF,
      normalized & 0xFF,
    ];
  }

  static List<int> currentEpochSeconds([DateTime? now]) {
    // Send the phone's LOCAL wall-clock as an epoch (UTC seconds + local UTC
    // offset). The clock hardware has no timezone, and alarm hour/minute are set
    // in local time, so transmitting local time keeps the clock face and alarm
    // matching aligned with the phone — and DST is handled here by the phone
    // rather than by a hand-set offset on the device.
    final dt = now ?? DateTime.now();
    final localSeconds =
        dt.millisecondsSinceEpoch ~/ 1000 + dt.timeZoneOffset.inSeconds;
    return uint32(localSeconds);
  }

  static int _byte(String field, int value) {
    if (value < 0 || value > 0xFF) {
      throw ArgumentError(
        '$field must be 0..255 for the alarm payload, got $value',
      );
    }
    return value;
  }

  static List<int> alarm(Alarm alarm) {
    // Validate rather than silently masking, so a corrupt field surfaces as a
    // sync error instead of writing a wrong value into the 0x02 frame.
    //
    // 7-byte frame: [id, hour, minute, dayMask, qrRequired, snoozeCount,
    // snoozeDuration]. bytes[5..6] (snooze allowance + length, in minutes) were
    // added in coordinated app+firmware changes so per-alarm snooze reaches the
    // clock. They stay backward-compatible in both directions: the firmware reads
    // each only under the matching `len >=` guard, and older firmware ignores any
    // trailing bytes it doesn't expect.
    return [
      _byte('id', alarm.id),
      _byte('hour', alarm.hour),
      _byte('minute', alarm.minute),
      _byte('dayMask', alarm.dayMask),
      alarm.qrRequired ? 1 : 0,
      _byte('snoozeCount', alarm.wireSnoozeCount),
      _byte('snoozeDuration', alarm.wireSnoozeDuration),
    ];
  }

  static List<int> clockSettings({
    required bool autoDim,
    required int sleepStartHour,
    required int sleepStartMinute,
    required int sleepEndHour,
    required int sleepEndMinute,
  }) {
    return [
      autoDim ? 1 : 0,
      sleepStartHour & 0xFF,
      sleepStartMinute & 0xFF,
      sleepEndHour & 0xFF,
      sleepEndMinute & 0xFF,
    ];
  }
}
