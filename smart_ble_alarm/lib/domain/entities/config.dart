import 'package:equatable/equatable.dart';

class Config extends Equatable {
  final int autoDim;
  final int sleepStart;
  final int sleepEnd;
  
  const Config({
    required this.autoDim,
    required this.sleepStart,
    required this.sleepEnd,
  });

  @override
  List<Object?> get props => [autoDim, sleepStart, sleepEnd];
}
