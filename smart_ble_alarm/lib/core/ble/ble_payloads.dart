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
    // 9-byte frame: [id, hour, minute, dayMask, qrRequired, snoozeCount,
    // snoozeDuration, volume, gradualWake]. Each trailing byte past [4] was added
    // in a coordinated app+firmware change so a per-alarm setting reaches the
    // clock — bytes[5..6] carry snooze (allowance + length, minutes) and
    // bytes[7..8] carry ring volume (1–100%) + gradual-wake fade (seconds). They
    // stay backward-compatible in both directions: the firmware reads each only
    // under the matching `len >=` guard, and older firmware ignores any trailing
    // bytes it doesn't expect.
    return [
      _byte('id', alarm.id),
      _byte('hour', alarm.hour),
      _byte('minute', alarm.minute),
      _byte('dayMask', alarm.dayMask),
      alarm.qrRequired ? 1 : 0,
      _byte('snoozeCount', alarm.wireSnoozeCount),
      _byte('snoozeDuration', alarm.wireSnoozeDuration),
      _byte('volume', alarm.wireVolume),
      _byte('gradualWake', alarm.wireGradualWake),
    ];
  }

  /// Clock-face display settings, command 0x06 → `[flags, theme, accent]`.
  ///
  /// `flags` bit0 = 24-hour time, bit1 = show seconds, bit2 = show date.
  /// `theme` 0 = dark, 1 = light. `accent` 0 = amber, 1 = blue, 2 = green,
  /// 3 = violet. The firmware reads each byte under a `len >=` guard, so the
  /// frame can grow later without breaking older clocks.
  static List<int> clockDisplaySettings({
    required bool use24h,
    required bool showSeconds,
    required bool showDate,
    required int theme,
    required int accent,
  }) {
    final flags = (use24h ? 0x01 : 0) |
        (showSeconds ? 0x02 : 0) |
        (showDate ? 0x04 : 0);
    return [flags, theme & 0x01, accent & 0x03];
  }
}
