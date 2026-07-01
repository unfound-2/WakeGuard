import 'package:equatable/equatable.dart';

class Alarm extends Equatable {
  final int id;
  final int hour;
  final int minute;
  final int dayMask;
  final bool qrRequired;
  
  const Alarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.dayMask,
    required this.qrRequired,
  });

  bool get isActive => (dayMask & 0x80) != 0;
  
  bool isDayActive(int dayIndex) {
    // dayIndex: 0 = Sun, 1 = Mon, ..., 6 = Sat
    return (dayMask & (1 << dayIndex)) != 0;
  }

  @override
  List<Object?> get props => [id, hour, minute, dayMask, qrRequired];

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'hour': hour,
      'minute': minute,
      'dayMask': dayMask,
      'qrRequired': qrRequired,
    };
  }

  factory Alarm.fromJson(Map<String, dynamic> json) {
    return Alarm(
      id: json['id'] as int,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      dayMask: json['dayMask'] as int,
      qrRequired: json['qrRequired'] as bool,
    );
  }
}
