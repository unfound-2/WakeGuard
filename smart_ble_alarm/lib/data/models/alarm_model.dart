import '../../domain/entities/alarm.dart';

class AlarmModel extends Alarm {
  const AlarmModel({
    required super.id,
    required super.hour,
    required super.minute,
    required super.dayMask,
    required super.qrRequired,
  });

  factory AlarmModel.fromBytes(List<int> bytes) {
    if (bytes.length < 5) throw Exception("Invalid bytes for alarm");
    return AlarmModel(
      id: bytes[0],
      hour: bytes[1],
      minute: bytes[2],
      dayMask: bytes[3],
      qrRequired: bytes[4] != 0,
    );
  }

  List<int> toBytes() {
    return [
      id,
      hour,
      minute,
      dayMask,
      qrRequired ? 1 : 0,
    ];
  }

  AlarmModel copyWith({
    int? id,
    int? hour,
    int? minute,
    int? dayMask,
    bool? qrRequired,
  }) {
    return AlarmModel(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      dayMask: dayMask ?? this.dayMask,
      qrRequired: qrRequired ?? this.qrRequired,
    );
  }
}
