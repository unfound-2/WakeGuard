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
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
    return uint32(timestamp);
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
    // sync error instead of writing a wrong value into the fixed 5-byte frame.
    return [
      _byte('id', alarm.id),
      _byte('hour', alarm.hour),
      _byte('minute', alarm.minute),
      _byte('dayMask', alarm.dayMask),
      alarm.qrRequired ? 1 : 0,
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
