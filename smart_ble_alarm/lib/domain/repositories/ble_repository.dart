import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract class BleRepository {
  Stream<BluetoothAdapterState> get adapterState;
  Stream<List<ScanResult>> get scanResults;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connectToDevice(BluetoothDevice device);
  Future<void> disconnectFromDevice(BluetoothDevice device);

  Stream<BluetoothConnectionState> connectionState(BluetoothDevice device);

  Future<void> sendCommand(BluetoothDevice device, int cmd, List<int> payload);
  Stream<List<int>> receiveFrames(BluetoothDevice device);

  /// Releases all resources held by this repository (open subscriptions and
  /// stream controllers). Call before discarding an instance — e.g. when the
  /// app swaps to a different backend — so nothing is leaked.
  Future<void> dispose();
}
