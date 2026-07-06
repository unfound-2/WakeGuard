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
  });

  bool get isActive => (dayMask & 0x80) != 0;

  /// Dismissal is gated behind an item photo rather than a QR scan.
  bool get usesItemScan => itemLabel != null && itemLabel!.trim().isNotEmpty;

  /// A non-empty display name, falling back to a sensible default when unset.
  String get displayName =>
      (label != null && label!.trim().isNotEmpty) ? label!.trim() : 'Alarm';

  /// Deterministic fingerprint of the fields that actually reach the clock over
  /// BLE — the fixed 0x02 payload: hour, minute, dayMask and the secured-dismiss
  /// flag. App-side-only metadata (label, item target, snooze) is deliberately
  /// excluded so cosmetic edits don't mark an alarm as out-of-sync. Computed by
  /// hand (not [Object.hash], whose seed isn't stable across runs) so it can be
  /// persisted and compared later to detect changes the clock hasn't received.
  int get syncHash =>
      ((hour & 0xFF) << 24) |
      ((minute & 0xFF) << 16) |
      ((dayMask & 0xFF) << 8) |
      (qrRequired ? 1 : 0);

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
    );
  }
}
