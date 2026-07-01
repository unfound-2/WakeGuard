import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../domain/repositories/ble_repository.dart';
import '../datasources/ble_framing.dart';

class BleRepositoryImpl implements BleRepository {
  static const String hm10ServiceUuid = "FFE0";
  static const String hm10CharacteristicUuid = "FFE1";

  BluetoothCharacteristic? _txRxCharacteristic;
  StreamSubscription? _characteristicSub;
  final StreamController<List<int>> _framesController = StreamController.broadcast();
  final List<int> _receiveBuffer = [];

  @override
  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  @override
  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;

  @override
  Future<void> startScan() async {
    await FlutterBluePlus.startScan(
      withServices: [Guid(hm10ServiceUuid)],
      timeout: const Duration(seconds: 15),
    );
  }

  @override
  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  @override
  Future<void> connectToDevice(BluetoothDevice device) async {
    await device.connect(license: License.nonprofit, autoConnect: true);
    await device.discoverServices();
    
    // Find HM-10 characteristic
    for (BluetoothService service in device.servicesList) {
      if (service.uuid.toString().toUpperCase().contains(hm10ServiceUuid)) {
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          if (characteristic.uuid.toString().toUpperCase().contains(hm10CharacteristicUuid)) {
            _txRxCharacteristic = characteristic;
            
            // Subscribe to notifications
            await characteristic.setNotifyValue(true);
            _characteristicSub = characteristic.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                _processIncomingBytes(value);
              }
            });
            break;
          }
        }
      }
    }
  }

  void _processIncomingBytes(List<int> data) {
    for (int byte in data) {
      if (byte == BleFraming.sof) {
        _receiveBuffer.clear();
      } else if (byte == BleFraming.eof) {
        _processFrame(List.from(_receiveBuffer));
        _receiveBuffer.clear();
      } else {
        _receiveBuffer.add(byte);
      }
    }
  }

  void _processFrame(List<int> frame) {
    _framesController.add(frame);
  }

  @override
  Future<void> disconnectFromDevice(BluetoothDevice device) async {
    await _characteristicSub?.cancel();
    _characteristicSub = null;
    _txRxCharacteristic = null;
    _receiveBuffer.clear();
    await device.disconnect();
  }

  @override
  Stream<BluetoothConnectionState> connectionState(BluetoothDevice device) {
    return device.connectionState;
  }

  @override
  Future<void> sendCommand(BluetoothDevice device, int cmd, List<int> payload) async {
    if (_txRxCharacteristic == null) {
      throw Exception("Characteristic not found. Are you connected?");
    }
    List<int> frame = BleFraming.encodeFrame(cmd, payload);
    
    // Send in chunks of 20 bytes (MTU limit)
    for (int i = 0; i < frame.length; i += 20) {
      int end = (i + 20 < frame.length) ? i + 20 : frame.length;
      List<int> chunk = frame.sublist(i, end);
      await _txRxCharacteristic!.write(chunk, withoutResponse: true);
      // Small delay between chunks for reliable transmission
      await Future.delayed(const Duration(milliseconds: 20));
    }
  }

  @override
  Stream<List<int>> receiveFrames(BluetoothDevice device) {
    return _framesController.stream;
  }
}
