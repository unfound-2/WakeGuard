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

  /// Deterministic fingerprint of the fields that actually reach the clock over
  /// BLE — the 0x02 payload: hour, minute, dayMask, the secured-dismiss flag and
  /// the snooze allowance + length. Purely app-side metadata (label, item target)
  /// is deliberately excluded so cosmetic edits don't mark an alarm out-of-sync.
  /// Computed by hand (not [Object.hash], whose seed isn't stable across runs) so
  /// it can be persisted and compared later to detect changes the clock hasn't
  /// received. Packs into 48 bits — safe on the 64-bit int this only ever runs on
  /// (a mobile BLE app, never web).
  int get syncHash =>
      ((hour & 0xFF) << 40) |
      ((minute & 0xFF) << 32) |
      ((dayMask & 0xFF) << 24) |
      ((qrRequired ? 1 : 0) << 16) |
      ((wireSnoozeCount & 0xFF) << 8) |
      (wireSnoozeDuration & 0xFF);

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
    );
  }
}
