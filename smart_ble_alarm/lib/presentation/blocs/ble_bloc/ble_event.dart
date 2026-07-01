import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:equatable/equatable.dart';

abstract class BleEvent extends Equatable {
  const BleEvent();
  
  @override
  List<Object?> get props => [];
}

class StartScanEvent extends BleEvent {}

class StopScanEvent extends BleEvent {}

class AutoConnectEvent extends BleEvent {
  final String deviceId;
  const AutoConnectEvent(this.deviceId);
  @override
  List<Object?> get props => [deviceId];
}

class DeviceFoundEvent extends BleEvent {
  final BluetoothDevice device;
  const DeviceFoundEvent(this.device);

  @override
  List<Object?> get props => [device];
}

class ConnectionStateChangedEvent extends BleEvent {
  final BluetoothConnectionState state;
  const ConnectionStateChangedEvent(this.state);

  @override
  List<Object?> get props => [state];
}

class ToggleSimulationEvent extends BleEvent {}

