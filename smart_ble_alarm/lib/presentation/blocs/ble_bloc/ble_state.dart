import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:equatable/equatable.dart';

abstract class BleState extends Equatable {
  const BleState();
  
  @override
  List<Object?> get props => [];
}

class BleDisconnected extends BleState {}

class BleScanning extends BleState {}

class BleConnecting extends BleState {}

class BleConnected extends BleState {
  final BluetoothDevice device;
  const BleConnected(this.device);

  @override
  List<Object?> get props => [device];
}

