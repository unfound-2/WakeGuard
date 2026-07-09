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
  /// `flags` bit0 = 24-hour time, bit1 = show seconds, bit2 = show (calendar)
  /// date, bit3 = show day-of-week, bits4-5 = date format (0 "MMM D", 1 "D MMM",
  /// 2 "MM/DD/YY", 3 "YYYY-MM-DD"). `theme` 0 = dark, 1 = light. `accent` 0 =
  /// amber, 1 = blue, 2 = green, 3 = violet. The firmware reads each byte under a
  /// `len >=` guard and the day-of-week / date-format bits are additive within the
  /// existing flags byte, so this stays compatible with older clocks (they ignore
  /// the extra bits) and older app builds (they simply leave those bits clear).
  static List<int> clockDisplaySettings({
    required bool use24h,
    required bool showSeconds,
    required bool showDate,
    required bool showDayOfWeek,
    required int dateFormat,
    required int theme,
    required int accent,
  }) {
    final flags = (use24h ? 0x01 : 0) |
        (showSeconds ? 0x02 : 0) |
        (showDate ? 0x04 : 0) |
        (showDayOfWeek ? 0x08 : 0) |
        ((dateFormat & 0x03) << 4);
    return [flags, theme & 0x01, accent & 0x03];
  }

  /// Weather for the clock face, command 0x0C → `[temp, condition]`.
  ///
  /// The clock has no network, so the phone fetches weather and pushes it here.
  /// `temp` is a SIGNED 8-bit whole degree in the user's chosen unit (the app
  /// converts to °C or °F before sending; the clock just prints the number + a
  /// degree ring, unit-agnostic). `condition` is a compact bucket the firmware
  /// knows how to draw: 0 clear, 1 partly cloudy, 2 cloudy, 3 rain, 4 snow,
  /// 5 thunder, 6 fog.
  static List<int> weather({required int temp, required int conditionCode}) {
    // Two's-complement low byte so -5 travels as 0xFB and the firmware's int8_t
    // cast reads it back as -5.
    final t = temp.clamp(-99, 99) & 0xFF;
    return [t, conditionCode & 0x07];
  }

  /// Weather "hide" frame, command 0x0C → `[0, 0xFF]`. The 0xFF condition tells
  /// the clock to blank its weather corner (the user turned weather off).
  static List<int> weatherHidden() => [0, 0xFF];

  /// Display-sleep schedule, command 0x0D → `[enabled, startHour, startMinute,
  /// endHour, endMinute]`.
  ///
  /// During the nightly window the clock blanks its panel (the ILI9341
  /// display-off opcode) so a dark room stays dark. The backlight LED is hardwired
  /// to 3.3V, so it can't be switched — a faint glow remains and a ringing alarm
  /// always re-lights the screen. The window may wrap past midnight (start later
  /// than end, e.g. 22:00 → 07:00). RAM-only on the clock: re-pushed every sync.
  static List<int> clockSleepSchedule({
    required bool enabled,
    required int startHour,
    required int startMinute,
    required int endHour,
    required int endMinute,
  }) {
    return [
      enabled ? 1 : 0,
      startHour & 0xFF,
      startMinute & 0xFF,
      endHour & 0xFF,
      endMinute & 0xFF,
    ];
  }
}
