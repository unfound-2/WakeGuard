import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:smart_ble_alarm/domain/repositories/ble_repository.dart';
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

  Future<void> _onStartScan(
    StartScanEvent event,
    Emitter<BleState> emit,
  ) async {
    _autoReconnectDeviceId = null;
    _isConnecting = false;
    _autoConnectAttempts = 0;
    emit(BleScanning());

    await _scanSubscription?.cancel();
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

  Future<void> _onStopScan(StopScanEvent event, Emitter<BleState> emit) async {
    _scanTimeoutTimer?.cancel();
    await bleRepository.stopScan();
    if (state is BleScanning) {
      emit(BleDisconnected());
    }
  }

  Future<void> _onAutoConnect(
    AutoConnectEvent event,
    Emitter<BleState> emit,
  ) async {
    // Drop a redundant overlapping auto-connect. Several places dispatch
    // ReconnectEvent (lifecycle resume, settings/alarm listeners, connectivity
    // retry) and two can pass ReconnectEvent's state guard together while still
    // BleDisconnected. A genuine retry from _onScanTimedOut nulls _scanSubscription
    // and clears _isConnecting first, so it is never blocked here.
    if (_scanSubscription != null || _isConnecting) return;

    _autoReconnectDeviceId = event.deviceId;

    if (event.deviceId == 'simulated_device') {
      final device = BluetoothDevice.fromId('simulated_device');
      _isConnecting = true;
      _connectedDevice = device;
      emit(BleConnecting());
      try {
        await bleRepository.connectToDevice(device);
      } catch (e) {
        _isConnecting = false;
        _connectedDevice = null;
        if (!isClosed) emit(BleDisconnected());
        return;
      }
      // Aborted (released/forgotten/superseded) while connecting.
      if (isClosed || _connectedDevice != device) {
        try {
          await bleRepository.disconnectFromDevice(device);
        } catch (_) {}
        return;
      }
      _finishConnect(device, emit);
      return;
    }

    emit(BleConnecting());

    await _scanSubscription?.cancel();
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
      await _scanSubscription?.cancel();
      _scanSubscription = null;
      emit(BleDisconnected());
    }
  }

  Future<void> _onDeviceFound(
    DeviceFoundEvent event,
    Emitter<BleState> emit,
  ) async {
    // Ignore a re-entrant match while a connect is already in flight, and stop
    // listening to further scan batches synchronously (before the first await)
    // so no second DeviceFoundEvent can be queued during stopScan().
    if (_isConnecting) return;
    _isConnecting = true;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    _scanTimeoutTimer?.cancel();
    await bleRepository.stopScan();
    // Drop any stale connection listener from a previous link before we start a
    // new one, so its late "disconnected" replay can't clobber the new link.
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    emit(BleConnecting());

    final device = event.device;
    // Tracked from here so Release/Forget can disconnect a device that is still
    // mid-connect, and so the post-await abort check below can detect that case.
    _connectedDevice = device;

    try {
      // connectToDevice completes only once services are discovered AND the FFE1
      // characteristic is subscribed (see BleRepositoryImpl._performConnect), so
      // it is safe to sync the clock the instant we emit BleConnected. We must
      // NOT emit BleConnected off the raw connectionState stream — that stream
      // both replays "disconnected" on subscribe (which would strand a live
      // link) and can report "connected" before discovery finishes.
      await bleRepository.connectToDevice(device);
    } catch (e) {
      _isConnecting = false;
      _connectedDevice = null;
      try {
        await bleRepository.disconnectFromDevice(device);
      } catch (_) {}
      if (!isClosed) emit(BleDisconnected());
      return;
    }

    // If we were released/forgotten (or a newer connect started) while awaiting,
    // abort: disconnect the device we just brought up and do not emit Connected.
    if (isClosed || _connectedDevice != device) {
      try {
        await bleRepository.disconnectFromDevice(device);
      } catch (_) {}
      return;
    }

    _finishConnect(device, emit);
  }

  /// Records a fully-established link and starts watching ONLY for future drops.
  void _finishConnect(BluetoothDevice device, Emitter<BleState> emit) {
    _isConnecting = false;
    _autoConnectAttempts = 0;
    // Remember whatever we actually connected to — including devices paired via
    // a fresh scan — so a background/foreground cycle can reconnect.
    _autoReconnectDeviceId = device.remoteId.str;

    // The connectionState stream replays its current value ("connected") on
    // subscribe, which _onConnectionStateChanged ignores; it acts only on a
    // later "disconnected" to surface an unexpected drop. Drop any stale listener
    // first so we never keep two feeding events into the bloc.
    _connectionSubscription?.cancel();
    _connectionSubscription = bleRepository.connectionState(device).listen((s) {
      add(ConnectionStateChangedEvent(s));
    });

    if (!isClosed) emit(BleConnected(device));
  }

  Future<void> _onConnectionStateChanged(
    ConnectionStateChangedEvent event,
    Emitter<BleState> emit,
  ) async {
    // This handler is a DISCONNECT detector only. "connected" is emitted inline
    // by _finishConnect once the characteristic is ready, and the stream replays
    // "connected" on subscribe, so we ignore every non-disconnect value here.
    if (event.state != BluetoothConnectionState.disconnected) return;
    // Only meaningful once a link is actually established; otherwise it's the
    // stream's initial replay during/after a connect attempt.
    if (_connectedDevice == null) return;
    _isConnecting = false;
    _connectedDevice = null;
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    // No automatic reconnect: the clock keeps running alarms on its own, so the
    // phone simply reports "disconnected". The link is restored on the next
    // ReconnectEvent (app resume) or a manual reconnect/scan.
    if (!isClosed) emit(BleDisconnected());
  }

  Future<void> _onToggleSimulation(
    ToggleSimulationEvent event,
    Emitter<BleState> emit,
  ) async {
    if (state is BleConnected &&
        _connectedDevice?.remoteId.str == 'simulated_device') {
      // Stop reconnecting to the simulator once the user leaves it, otherwise a
      // later resume would silently drop back into simulation.
      _autoReconnectDeviceId = null;
      try {
        await bleRepository.disconnectFromDevice(_connectedDevice!);
      } catch (_) {}
    } else {
      add(const AutoConnectEvent('simulated_device'));
    }
  }

  Future<void> _onScanTimedOut(
    ScanTimedOutEvent event,
    Emitter<BleState> emit,
  ) async {
    // A connect that already started owns the flow; a scan-window timeout that
    // was queued just before the device was found must not tear it down.
    if (_isConnecting) return;
    if (state is BleScanning || state is BleConnecting) {
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
      emit(
        _autoReconnectDeviceId == null
            ? const BleScanTimedOut()
            : const BleDisconnected(),
      );
    }
  }

  /// App returned to the foreground: restore the link to the remembered device.
  /// Skipped when there's nothing to reconnect to, or a connect/scan is already
  /// underway, or we're already connected.
  Future<void> _onReconnect(
    ReconnectEvent event,
    Emitter<BleState> emit,
  ) async {
    final deviceId = _autoReconnectDeviceId;
    if (deviceId == null) return;
    if (state is BleConnected ||
        state is BleConnecting ||
        state is BleScanning) {
      return;
    }
    if (_isConnecting || _scanSubscription != null) return;
    _autoConnectAttempts = 0;
    add(AutoConnectEvent(deviceId));
  }

  /// App went to the background: drop the connection to save battery but keep
  /// [_autoReconnectDeviceId] so [ReconnectEvent] can restore it on resume.
  Future<void> _onReleaseConnection(
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

  Future<void> _onForgetDevice(
    ForgetDeviceEvent event,
    Emitter<BleState> emit,
  ) async {
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

  void _startScanTimeout([Duration duration = const Duration(seconds: 16)]) {
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(duration, () {
      add(ScanTimedOutEvent());
    });
  }

  @override
  Future<void> close() async {
    _scanTimeoutTimer?.cancel();
    await _scanSubscription?.cancel();
    await _connectionSubscription?.cancel();
    try {
      await bleRepository.stopScan();
    } catch (_) {}
    return super.close();
  }
}
