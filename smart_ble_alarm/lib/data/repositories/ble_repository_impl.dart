import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../domain/repositories/ble_repository.dart';
import '../datasources/ble_framing.dart';

class BleRepositoryImpl implements BleRepository {
  static const String hm10ServiceUuid = "FFE0";
  static const String hm10CharacteristicUuid = "FFE1";

  BluetoothCharacteristic? _txRxCharacteristic;
  StreamSubscription? _characteristicSub;
  final StreamController<List<int>> _framesController =
      StreamController.broadcast();
  final List<int> _receiveBuffer = [];

  // Serializes all outgoing writes. Because a frame is transmitted as several
  // 20-byte chunks over a single characteristic, two concurrent callers (e.g.
  // an auto-sync and a manual "Sync Now") must never interleave their chunks —
  // that would corrupt the on-wire frame structure. Every write chains onto the
  // previous one so they run strictly one at a time.
  Future<void> _writeChain = Future.value();

  // Serializes connect attempts. connectToDevice mutates shared state
  // (_txRxCharacteristic, _characteristicSub, _receiveBuffer); two overlapping
  // calls would clobber each other and orphan a subscription, so each connect
  // chains onto the previous one.
  Future<void> _connectChain = Future.value();

  @override
  Stream<BluetoothAdapterState> get adapterState =>
      FlutterBluePlus.adapterState;

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
  Future<void> connectToDevice(BluetoothDevice device) {
    final result = _connectChain.then((_) => _performConnect(device));
    _connectChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _performConnect(BluetoothDevice device) async {
    await _characteristicSub?.cancel();
    _characteristicSub = null;
    _txRxCharacteristic = null;
    _receiveBuffer.clear();

    await device.connect(
      license: License.nonprofit,
      autoConnect: false,
      timeout: const Duration(seconds: 15),
    );
    // discoverServices()/setNotifyValue() have no built-in timeout. HM-10 GATT
    // discovery occasionally stalls AFTER a successful low-level connect; without
    // a cap the caller (the bloc) would await forever and the UI would sit on
    // "Reconnecting…" with no recovery. Bound them and disconnect on timeout so
    // the failure propagates and the bloc can reset to Disconnected.
    final services = await device.discoverServices().timeout(
      const Duration(seconds: 12),
      onTimeout: () async {
        await device.disconnect();
        throw TimeoutException('Service discovery timed out');
      },
    );

    // Find HM-10 characteristic
    for (BluetoothService service in services) {
      if (service.uuid.toString().toUpperCase().contains(hm10ServiceUuid)) {
        for (BluetoothCharacteristic characteristic
            in service.characteristics) {
          if (characteristic.uuid.toString().toUpperCase().contains(
            hm10CharacteristicUuid,
          )) {
            _txRxCharacteristic = characteristic;

            // Subscribe to notifications
            await characteristic.setNotifyValue(true).timeout(
              const Duration(seconds: 8),
              onTimeout: () async {
                await device.disconnect();
                throw TimeoutException('Enabling notifications timed out');
              },
            );
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

    if (_txRxCharacteristic == null) {
      await device.disconnect();
      throw Exception("HM-10 UART characteristic FFE1 was not found.");
    }
  }

  void _processIncomingBytes(List<int> data) {
    _receiveBuffer.addAll(data);
    final frames = BleFraming.decodeFrames(_receiveBuffer);
    for (final frame in frames) {
      _framesController.add(frame);
    }
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
  Future<void> sendCommand(BluetoothDevice device, int cmd, List<int> payload) {
    // Queue this write behind any in-flight write. The returned future carries
    // this call's own success/error, while `_writeChain` swallows errors so one
    // failed write never stalls the queue for subsequent commands.
    final result = _writeChain.then((_) => _performWrite(cmd, payload));
    _writeChain = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> _performWrite(int cmd, List<int> payload) async {
    if (_txRxCharacteristic == null) {
      throw Exception("Characteristic not found. Are you connected?");
    }
    final characteristic = _txRxCharacteristic!;
    List<int> frame = BleFraming.encodeFrame(cmd, payload);

    // Prefer acknowledged writes when the characteristic supports them: a
    // write-with-response awaits the peer's confirmation, so a congested BLE link
    // can't silently drop a chunk and corrupt a multi-chunk frame mid-sync (the
    // clock would then reject that frame and the alarm/setting would go missing).
    // Fall back to write-without-response only when that's all FFE1 exposes.
    final acked = characteristic.properties.write;

    // Send in chunks of 20 bytes (default ATT MTU minus 3-byte header).
    for (int i = 0; i < frame.length; i += 20) {
      int end = (i + 20 < frame.length) ? i + 20 : frame.length;
      List<int> chunk = frame.sublist(i, end);
      await characteristic.write(chunk, withoutResponse: !acked);
      // Acked writes are self-pacing; unacked ones need a gap so the HM-10's
      // 64-byte UART buffer can drain between chunks.
      if (!acked) {
        await Future.delayed(const Duration(milliseconds: 20));
      }
    }
  }

  @override
  Stream<List<int>> receiveFrames(BluetoothDevice device) {
    return _framesController.stream;
  }

  @override
  Future<void> dispose() async {
    await _characteristicSub?.cancel();
    _characteristicSub = null;
    _txRxCharacteristic = null;
    _receiveBuffer.clear();
    await _framesController.close();
  }
}
