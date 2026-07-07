import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../../domain/repositories/ble_repository.dart';
import 'ble_event.dart';
import 'ble_state.dart';

class BleConnectionBloc extends Bloc<BleEvent, BleState> {
  final BleRepository bleRepository;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _connectionSubscription;
  Timer? _scanTimeoutTimer;
  BluetoothDevice? _connectedDevice;
  // The last device we successfully connected to (or were asked to auto-connect
  // to). Kept across background/foreground so [ReconnectEvent] can restore the
  // link on resume. Cleared only by [ForgetDeviceEvent]. There is deliberately
  // no periodic reconnect timer: the clock runs alarms on its own hardware, so
  // the phone stays disconnected in the background to save battery and only
  // reconnects when the app is opened or an action needs the link.
  String? _autoReconnectDeviceId;
  // Guards against overlapping connect attempts: a second scan batch can fire
  // another DeviceFoundEvent while the first connect is still in flight.
  bool _isConnecting = false;
  // Bounded auto-connect retries. BLE advertising is intermittent, so a single
  // scan on app-open often misses even when the clock is in range; we retry a
  // few times before giving up. This is NOT a permanent reconnect loop — after
  // [_maxAutoConnectAttempts] scans we stop and wait for the next app-open or
  // manual reconnect (the clock rings alarms on its own regardless).
  int _autoConnectAttempts = 0;
  static const int _maxAutoConnectAttempts = 3;

  BleConnectionBloc({required this.bleRepository}) : super(BleDisconnected()) {
    on<StartScanEvent>(_onStartScan);
    on<StopScanEvent>(_onStopScan);
    on<DeviceFoundEvent>(_onDeviceFound);
    on<ConnectionStateChangedEvent>(_onConnectionStateChanged);
    on<ToggleSimulationEvent>(_onToggleSimulation);
    on<AutoConnectEvent>(_onAutoConnect);
    on<ScanTimedOutEvent>(_onScanTimedOut);
    on<ForgetDeviceEvent>(_onForgetDevice);
    on<ReconnectEvent>(_onReconnect);
    on<ReleaseConnectionEvent>(_onReleaseConnection);
  }

  void _onStartScan(StartScanEvent event, Emitter<BleState> emit) async {
    _autoReconnectDeviceId = null;
    _isConnecting = false;
    _autoConnectAttempts = 0;
    emit(BleScanning());

    _scanSubscription?.cancel();
    _scanSubscription = bleRepository.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (_isTargetClock(r)) {
          add(DeviceFoundEvent(r.device));
          break;
        }
      }
    });

    try {
      _startScanTimeout();
      await bleRepository.startScan();
    } catch (e) {
      _scanTimeoutTimer?.cancel();
      emit(BleDisconnected());
    }
  }

  void _onStopScan(StopScanEvent event, Emitter<BleState> emit) async {
    _scanTimeoutTimer?.cancel();
    await bleRepository.stopScan();
    if (state is BleScanning) {
      emit(BleDisconnected());
    }
  }

  void _onAutoConnect(AutoConnectEvent event, Emitter<BleState> emit) async {
    _autoReconnectDeviceId = event.deviceId;
    _isConnecting = false;

    if (event.deviceId == 'simulated_device') {
      final device = BluetoothDevice.fromId('simulated_device');
      _connectedDevice = device;

      _connectionSubscription?.cancel();
      _connectionSubscription = bleRepository.connectionState(device).listen((
        connectionState,
      ) {
        add(ConnectionStateChangedEvent(connectionState));
      });

      try {
        await bleRepository.connectToDevice(device);
      } catch (e) {
        emit(BleDisconnected());
      }
      return;
    }

    emit(BleConnecting());

    _scanSubscription?.cancel();
    _scanSubscription = bleRepository.scanResults.listen((results) {
      for (ScanResult r in results) {
        if (r.device.remoteId.str == event.deviceId) {
          add(DeviceFoundEvent(r.device));
          break;
        }
      }
    });

    try {
      // Shorter per-attempt window than a manual pairing scan, since auto-connect
      // may run several attempts back-to-back.
      _startScanTimeout(const Duration(seconds: 12));
      await bleRepository.startScan();
    } catch (e) {
      _scanTimeoutTimer?.cancel();
      emit(BleDisconnected());
    }
  }

  void _onDeviceFound(DeviceFoundEvent event, Emitter<BleState> emit) async {
    // Ignore a re-entrant match while a connect is already in flight, and stop
    // listening to further scan batches synchronously (before the first await)
    // so no second DeviceFoundEvent can be queued during stopScan().
    if (_isConnecting) return;
    _isConnecting = true;
    _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanTimeoutTimer?.cancel();
    await bleRepository.stopScan();
    emit(BleConnecting());

    _connectedDevice = event.device;
    _connectionSubscription?.cancel();
    _connectionSubscription = bleRepository
        .connectionState(event.device)
        .listen((connectionState) {
          add(ConnectionStateChangedEvent(connectionState));
        });

    try {
      await bleRepository.connectToDevice(event.device);
    } catch (e) {
      _isConnecting = false;
      emit(BleDisconnected());
    }
  }

  void _onConnectionStateChanged(
    ConnectionStateChangedEvent event,
    Emitter<BleState> emit,
  ) {
    if (event.state == BluetoothConnectionState.connected &&
        _connectedDevice != null) {
      _isConnecting = false;
      _autoConnectAttempts = 0;
      // Remember whatever we actually connected to — including devices paired
      // via a fresh scan — so a background/foreground cycle can reconnect.
      _autoReconnectDeviceId = _connectedDevice!.remoteId.str;
      emit(BleConnected(_connectedDevice!));
    } else if (event.state == BluetoothConnectionState.disconnected) {
      _isConnecting = false;
      _connectedDevice = null;
      // No automatic reconnect: the clock keeps running alarms on its own, so
      // the phone simply reports "disconnected". The link is restored on the
      // next ReconnectEvent (app resume) or a manual reconnect/scan.
      emit(BleDisconnected());
    }
  }

  void _onToggleSimulation(
    ToggleSimulationEvent event,
    Emitter<BleState> emit,
  ) async {
    if (state is BleConnected &&
        _connectedDevice?.remoteId.str == 'simulated_device') {
      try {
        await bleRepository.disconnectFromDevice(_connectedDevice!);
      } catch (_) {}
    } else {
      add(const AutoConnectEvent('simulated_device'));
    }
  }

  void _onScanTimedOut(ScanTimedOutEvent event, Emitter<BleState> emit) async {
    if (state is BleScanning || state is BleConnecting) {
      _isConnecting = false;
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      await bleRepository.stopScan();

      // Auto-connect to a remembered clock gets a few bounded retries before
      // giving up: BLE advertising is intermittent, so one scan on app-open
      // often misses even when the clock is in range. Still not a permanent
      // loop — after [_maxAutoConnectAttempts] we give up quietly (the
      // remembered device is kept, so opening the app again retries).
      if (_autoReconnectDeviceId != null &&
          _autoReconnectDeviceId != 'simulated_device' &&
          _autoConnectAttempts < _maxAutoConnectAttempts) {
        _autoConnectAttempts++;
        add(AutoConnectEvent(_autoReconnectDeviceId!));
        return;
      }
      _autoConnectAttempts = 0;
      emit(BleDisconnected());
    }
  }

  /// App returned to the foreground: restore the link to the remembered device.
  /// Skipped when there's nothing to reconnect to, or a connect/scan is already
  /// underway, or we're already connected.
  void _onReconnect(ReconnectEvent event, Emitter<BleState> emit) async {
    final deviceId = _autoReconnectDeviceId;
    if (deviceId == null) return;
    if (state is BleConnected || state is BleConnecting || state is BleScanning) {
      return;
    }
    _autoConnectAttempts = 0;
    add(AutoConnectEvent(deviceId));
  }

  /// App went to the background: drop the connection to save battery but keep
  /// [_autoReconnectDeviceId] so [ReconnectEvent] can restore it on resume.
  void _onReleaseConnection(
    ReleaseConnectionEvent event,
    Emitter<BleState> emit,
  ) async {
    _isConnecting = false;
    _scanTimeoutTimer?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    final device = _connectedDevice;
    _connectedDevice = null;
    try {
      await bleRepository.stopScan();
    } catch (_) {}
    if (device != null) {
      try {
        await bleRepository.disconnectFromDevice(device);
      } catch (_) {}
    }
    emit(BleDisconnected());
  }

  void _onForgetDevice(ForgetDeviceEvent event, Emitter<BleState> emit) async {
    // Stop every reconnect/scan pathway first so the imminent disconnect can't
    // schedule a reconnect or resurrect the connection.
    _autoReconnectDeviceId = null;
    _isConnecting = false;
    _scanTimeoutTimer?.cancel();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    // Cancel the connection listener before disconnecting so the resulting
    // "disconnected" event is not routed back into _onConnectionStateChanged.
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    final device = _connectedDevice;
    _connectedDevice = null;
    try {
      await bleRepository.stopScan();
    } catch (_) {}
    if (device != null) {
      try {
        await bleRepository.disconnectFromDevice(device);
      } catch (_) {}
    }

    emit(BleDisconnected());
  }

  bool _isTargetClock(ScanResult result) {
    final platformName = result.device.platformName.toLowerCase();
    final advertisedName = result.advertisementData.advName.toLowerCase();
    final serviceUuids = result.advertisementData.serviceUuids
        .map((uuid) => uuid.toString().toUpperCase())
        .join(',');

    return platformName.contains('hm-10') ||
        platformName.contains('hmsoft') ||
        platformName.contains('smart clock') ||
        platformName.contains('wg clock') ||
        platformName.contains('wakeguard') ||
        advertisedName.contains('hm-10') ||
        advertisedName.contains('hmsoft') ||
        advertisedName.contains('smart clock') ||
        advertisedName.contains('wg clock') ||
        advertisedName.contains('wakeguard') ||
        serviceUuids.contains('FFE0');
  }

  void _startScanTimeout([
    Duration duration = const Duration(seconds: 16),
  ]) {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(duration, () {
      add(ScanTimedOutEvent());
    });
  }

  @override
  Future<void> close() {
    _scanTimeoutTimer?.cancel();
    _scanSubscription?.cancel();
    _connectionSubscription?.cancel();
    return super.close();
  }
}
