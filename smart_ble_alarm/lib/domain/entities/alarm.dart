import 'package:equatable/equatable.dart';

class Alarm extends Equatable {
  final int id;
  final int hour;
  final int minute;
  final int dayMask;

  /// Whether the clock must enforce a secured (token-gated) dismissal. True for
  /// both QR-code and item-scan alarms — it maps to the hardware "requires
  /// token" flag. The *method* (QR vs item) is a phone-side concern below.
  final bool qrRequired;

  /// On-device image-recognition target. When set, the alarm is dismissed by
  /// photographing this object instead of scanning a QR code. Null = QR method.
  final String? itemLabel;

  /// Human-readable reminder of what to find, shown on the dismissal screen
  /// (e.g. "the toothbrush in the bathroom").
  final String? itemDescription;

  /// Optional human-friendly name for the alarm ("Wake up", "Meds"). Phone-side
  /// only — never sent over BLE, so it doesn't affect firmware compatibility.
  final String? label;

  /// Whether the user is allowed to snooze this alarm before the scan-gated
  /// dismissal must be completed. Phone-side metadata.
  final bool snoozeEnabled;

  /// How many times the alarm may be snoozed when [snoozeEnabled]. Ignored when
  /// snooze is disabled. 0 means "not set".
  final int snoozeMaxCount;

  /// How long each snooze lasts, in minutes, when [snoozeEnabled]. Sent to the
  /// clock (byte[6] of the 0x02 frame) so the hardware snooze interval matches
  /// the app. Defaults to 5, matching the firmware's historical constant.
  final int snoozeDurationMinutes;

  /// Ring loudness as a percentage (1–100). Sent to the clock (byte[7] of the
  /// 0x02 frame), which maps it to the speaker's PWM duty cycle. Applies to
  /// every ring regardless of snooze. Defaults to 80.
  final int volumePercent;

  /// Gradual-wake fade-in length in seconds (0 = no fade — ring starts at full
  /// [volumePercent]). Sent to the clock (byte[8] of the 0x02 frame); the
  /// hardware ramps the volume from a soft floor up to [volumePercent] over this
  /// window each time the alarm (or a snooze resume) begins sounding.
  final int gradualWakeSeconds;

  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.dayMask,
    required this.qrRequired,
    this.itemLabel,
    this.itemDescription,
    this.label,
    this.snoozeEnabled = false,
    this.snoozeMaxCount = 0,
    this.snoozeDurationMinutes = 5,
    this.volumePercent = 80,
    this.gradualWakeSeconds = 0,
  });

  bool get isActive => (dayMask & 0x80) != 0;

  /// Dismissal is gated behind an item photo rather than a QR scan.
  bool get usesItemScan => itemLabel != null && itemLabel!.trim().isNotEmpty;

  /// A non-empty display name, falling back to a sensible default when unset.
  String get displayName =>
      (label != null && label!.trim().isNotEmpty) ? label!.trim() : 'Alarm';

  /// The per-alarm snooze allowance that travels to the clock in byte[5] of the
  /// 0x02 frame: how many times the ring may be snoozed (0 = snooze disabled).
  /// Collapses the two app-side fields into the single value the firmware needs
  /// and is the one source of truth shared by [BlePayloads.alarm] and [syncHash],
  /// so the wire byte and the "needs re-sync?" check can never disagree.
  int get wireSnoozeCount => snoozeEnabled ? snoozeMaxCount.clamp(0, 255) : 0;

  /// The snooze length (minutes) that travels to the clock in byte[6] of the
  /// 0x02 frame. Like [wireSnoozeCount] it collapses to 0 when snooze is off, so
  /// editing it while disabled doesn't spuriously mark the alarm out-of-sync; the
  /// firmware reads 0 as "use the clock's default length".
  int get wireSnoozeDuration =>
      snoozeEnabled ? snoozeDurationMinutes.clamp(1, 255) : 0;

  /// The ring loudness (1–100) that travels to the clock in byte[7] of the 0x02
  /// frame. Always sent (independent of snooze); clamped so a corrupt value can't
  /// silence or overflow the wire byte. The firmware reads 0 as "use the clock
  /// default", but the app always sends an explicit level.
  int get wireVolume => volumePercent.clamp(1, 100);

  /// The gradual-wake fade length (seconds) that travels to the clock in byte[8]
  /// of the 0x02 frame. 0 = no fade (ring at full volume immediately).
  int get wireGradualWake => gradualWakeSeconds.clamp(0, 255);

  /// Deterministic fingerprint of the exact bytes that reach the clock in the
  /// 0x02 payload — hour, minute, dayMask, the secured-dismiss flag, the snooze
  /// allowance + length, and the ring volume + gradual-wake fade. Purely app-side
  /// metadata (label, item target) is deliberately excluded so cosmetic edits
  /// don't mark an alarm out-of-sync. Folded with FNV-1a (not [Object.hash],
  /// whose seed isn't stable across runs) so it can be persisted and compared
  /// later to detect changes the clock hasn't received; the 32-bit result is
  /// always positive, so there's no sign-bit hazard as fields are added.
  ///
  /// NOTE: changing this fold (as adding volume/fade did) re-marks every alarm
  /// out-of-sync exactly once — they harmlessly re-send on the next connect.
  int get syncHash {
    const int fnvPrime = 0x01000193;
    int h = 0x811c9dc5;
    for (final b in <int>[
      hour & 0xFF,
      minute & 0xFF,
      dayMask & 0xFF,
      qrRequired ? 1 : 0,
      wireSnoozeCount & 0xFF,
      wireSnoozeDuration & 0xFF,
      wireVolume & 0xFF,
      wireGradualWake & 0xFF,
    ]) {
      h = (h ^ b) & 0xFFFFFFFF;
      h = (h * fnvPrime) & 0xFFFFFFFF;
    }
    return h;
  }

  bool isDayActive(int dayIndex) {
    // dayIndex: 0 = Sun, 1 = Mon, ..., 6 = Sat
    return (dayMask & (1 << dayIndex)) != 0;
  }

  Alarm copyWith({
    int? id,
    int? hour,
    int? minute,
    int? dayMask,
    bool? qrRequired,
    String? itemLabel,
    String? itemDescription,
    String? label,
    bool? snoozeEnabled,
    int? snoozeMaxCount,
    int? snoozeDurationMinutes,
    int? volumePercent,
    int? gradualWakeSeconds,
    // copyWith can't otherwise set the nullable item fields back to null.
    bool clearItem = false,
    bool clearLabel = false,
  }) {
    return Alarm(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      dayMask: dayMask ?? this.dayMask,
      qrRequired: qrRequired ?? this.qrRequired,
      itemLabel: clearItem ? null : (itemLabel ?? this.itemLabel),
      itemDescription: clearItem
          ? null
          : (itemDescription ?? this.itemDescription),
      label: clearLabel ? null : (label ?? this.label),
      snoozeEnabled: snoozeEnabled ?? this.snoozeEnabled,
      snoozeMaxCount: snoozeMaxCount ?? this.snoozeMaxCount,
      snoozeDurationMinutes:
          snoozeDurationMinutes ?? this.snoozeDurationMinutes,
      volumePercent: volumePercent ?? this.volumePercent,
      gradualWakeSeconds: gradualWakeSeconds ?? this.gradualWakeSeconds,
    );
  }

  @override
  List<Object?> get props => [
    id,
    hour,
    minute,
    dayMask,
    qrRequired,
    itemLabel,
    itemDescription,
    label,
    snoozeEnabled,
    snoozeMaxCount,
    snoozeDurationMinutes,
    volumePercent,
    gradualWakeSeconds,
  ];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hour': hour,
      'minute': minute,
      'dayMask': dayMask,
      'qrRequired': qrRequired,
      if (itemLabel != null) 'itemLabel': itemLabel,
      if (itemDescription != null) 'itemDescription': itemDescription,
      if (label != null) 'label': label,
      if (snoozeEnabled) 'snoozeEnabled': snoozeEnabled,
      if (snoozeMaxCount != 0) 'snoozeMaxCount': snoozeMaxCount,
      if (snoozeDurationMinutes != 5)
        'snoozeDurationMinutes': snoozeDurationMinutes,
      // Defaults omitted so unchanged alarms keep a compact JSON footprint.
      if (volumePercent != 80) 'volumePercent': volumePercent,
      if (gradualWakeSeconds != 0) 'gradualWakeSeconds': gradualWakeSeconds,
    };
  }

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'] as int,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      dayMask: json['dayMask'] as int,
      qrRequired: json['qrRequired'] as bool,
      itemLabel: json['itemLabel'] as String?,
      itemDescription: json['itemDescription'] as String?,
      label: json['label'] as String?,
      snoozeEnabled: json['snoozeEnabled'] as bool? ?? false,
      snoozeMaxCount: json['snoozeMaxCount'] as int? ?? 0,
      snoozeDurationMinutes: json['snoozeDurationMinutes'] as int? ?? 5,
      volumePercent: json['volumePercent'] as int? ?? 80,
      gradualWakeSeconds: json['gradualWakeSeconds'] as int? ?? 0,
    );
  }
}
