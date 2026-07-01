import '../../domain/entities/config.dart';

class ConfigModel extends Config {
  const ConfigModel({
    required super.autoDim,
    required super.sleepStart,
    required super.sleepEnd,
  });

  factory ConfigModel.fromBytes(List<int> bytes) {
    if (bytes.length < 3) throw Exception("Invalid bytes for config");
    return ConfigModel(
      autoDim: bytes[0],
      sleepStart: bytes[1],
      sleepEnd: bytes[2],
    );
  }

  List<int> toBytes() {
    return [
      autoDim,
      sleepStart,
      sleepEnd,
    ];
  }

  ConfigModel copyWith({
    int? autoDim,
    int? sleepStart,
    int? sleepEnd,
  }) {
    return ConfigModel(
      autoDim: autoDim ?? this.autoDim,
      sleepStart: sleepStart ?? this.sleepStart,
      sleepEnd: sleepEnd ?? this.sleepEnd,
    );
  }
}
