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

class ScanTimedOutEvent extends BleEvent {}

/// Disconnect from the current device and stop all auto-reconnect activity.
/// Used by "Forget Device" so the app fully releases the clock instead of
/// silently reconnecting to it.
class ForgetDeviceEvent extends BleEvent {}

/// Reconnect to the last-known device (if any) when the app returns to the
/// foreground. No-op when already connected/connecting or no device is
/// remembered. The clock runs alarms autonomously, so the phone only needs a
/// link while the app is open — this re-establishes it on resume.
class ReconnectEvent extends BleEvent {}

/// Release the radio when the app goes to the background: disconnect and stop
/// scanning, but *keep* the remembered device so [ReconnectEvent] can restore
/// the link on resume. This is the battery-saving counterpart to
/// [ForgetDeviceEvent], which instead forgets the device entirely.
class ReleaseConnectionEvent extends BleEvent {}
