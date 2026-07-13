import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';

class SimulatedBleRepositoryImpl implements BleRepository {
  final StreamController<List<ScanResult>> _scanResultsController =
      StreamController.broadcast();
  final StreamController<BluetoothConnectionState> _connectionStateController =
      StreamController.broadcast();
  final StreamController<List<int>> _receiveFramesController =
      StreamController.broadcast();

  bool _isConnected = false;

  @override
  Stream<BluetoothAdapterState> get adapterState async* {
    yield BluetoothAdapterState.on;
  }

  @override
  Stream<List<ScanResult>> get scanResults => _scanResultsController.stream;

  @override
  Future<void> startScan() async {
    // Simulate finding the device
    await Future.delayed(const Duration(milliseconds: 500));
    _scanResultsController.add([
      ScanResult(
        device: BluetoothDevice.fromId('simulated_device'),
        advertisementData: AdvertisementData(
          advName: 'Smart Clock (SIM)',
          txPowerLevel: 0,
          appearance: null,
          connectable: true,
          manufacturerData: {},
          serviceData: {},
          serviceUuids: [],
        ),
        rssi: -50,
        timeStamp: DateTime.now(),
      ),
    ]);
  }

  @override
  Future<void> stopScan() async {
    // Do nothing
  }

  @override
  Future<void> connectToDevice(BluetoothDevice device) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _isConnected = true;
    _connectionStateController.add(BluetoothConnectionState.connected);
  }

  @override
  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _isConnected = false;
    _connectionStateController.add(BluetoothConnectionState.disconnected);
  }

  @override
  Stream<BluetoothConnectionState> connectionState(BluetoothDevice device) {
    return _connectionStateController.stream;
  }

  @override
  Future<void> sendCommand(
    BluetoothDevice device,
    int cmd,
    List<int> payload,
  ) async {
    if (!_isConnected) {
      throw Exception(
        "Simulator: Characteristic not found. Are you connected?",
      );
    }

    // Simulate processing time
    await Future.delayed(const Duration(milliseconds: 100));

    // Respond with appropriate success return code based on the spec
    int returnCode;
    switch (cmd) {
      case 0x01:
        returnCode = 0x81;
        break; // TIME_SYNC_WRITE
      case 0x02:
        returnCode = 0x82;
        break; // ALARM_DB_ADD
      case 0x03:
        returnCode = 0x83;
        break; // ALARM_DB_DEL
      case 0x04:
        returnCode = 0x84;
        break; // SYNC_START
      case 0x05:
        returnCode = 0x85;
        break; // SYNC_END
      case 0x06:
        returnCode = 0x86;
        break; // SETTINGS_WRITE
      case 0x07:
        returnCode = 0x87;
        break; // QR_KEY_WRITE
      case 0x09:
        returnCode = 0x89;
        break; // ALARM_DISMISS
      case 0x0A:
        returnCode = 0x8A;
        break; // TIMER_SET
      case 0x0B:
        returnCode = 0x8B;
        break; // TIMER_STOP
      default:
        returnCode = 0x84;
        break; // fallback
    }

    List<int> responsePayload = [];
    if (cmd == 0x02 && payload.isNotEmpty) {
      responsePayload.add(payload[0]); // Return added alarm's ID
    }

    _receiveFramesController.add([
      returnCode,
      responsePayload.length,
      ...responsePayload,
    ]);
  }

  @override
  Stream<List<int>> receiveFrames(BluetoothDevice device) {
    return _receiveFramesController.stream;
  }

  @override
  Future<void> dispose() async {
    _isConnected = false;
    await _scanResultsController.close();
    await _connectionStateController.close();
    await _receiveFramesController.close();
  }
}
