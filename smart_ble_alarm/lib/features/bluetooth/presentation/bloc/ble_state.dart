import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:equatable/equatable.dart';

abstract class BleState extends Equatable {
  const BleState();

  @override
  List<Object?> get props => [];
}

class BleDisconnected extends BleState {
  const BleDisconnected();
}

class BleScanTimedOut extends BleDisconnected {
  const BleScanTimedOut();
}

class BleScanning extends BleState {
  const BleScanning();
}

class BleConnecting extends BleState {
  const BleConnecting();
}

class BleConnected extends BleState {
  final BluetoothDevice device;
  const BleConnected(this.device);

  @override
  List<Object?> get props => [device];
}
